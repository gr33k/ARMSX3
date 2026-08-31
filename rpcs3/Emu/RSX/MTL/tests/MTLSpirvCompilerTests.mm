#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "../MTLSpirvCompiler.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <span>
#include <string>
#include <vector>

namespace
{
	using namespace rsx::mtl;

	constexpr const char* spirv_cross_revision = "6c09849fe88c48eaed08413aa022aaa136a3a057";

	[[noreturn]] void fail(const std::string& message)
	{
		std::cerr << "MTL SPIR-V translation test failed: " << message << '\n';
		std::exit(1);
	}

	void require(const bool condition, const std::string& message)
	{
		if (!condition)
		{
			fail(message);
		}
	}

	std::vector<std::uint32_t> load_spirv(const char* path)
	{
		std::ifstream stream(path, std::ios::binary | std::ios::ate);
		require(stream.good(), std::string("cannot open ") + path);
		const std::streamsize byte_count = stream.tellg();
		require(byte_count > 0 && byte_count % 4 == 0, std::string("invalid SPIR-V size for ") + path);

		std::vector<std::uint32_t> words(static_cast<std::size_t>(byte_count) / 4);
		stream.seekg(0);
		stream.read(reinterpret_cast<char*>(words.data()), byte_count);
		require(stream.good(), std::string("cannot read ") + path);
		return words;
	}

	shader_source make_vertex_source(const std::span<const std::uint32_t> words)
	{
		shader_source source;
		source.spirv = words;
		source.metadata.stage = shader_stage::vertex;
		source.metadata.policy.spirv_cross_revision = spirv_cross_revision;
		source.metadata.resources = {{
			.stage = shader_stage::vertex,
			.kind = resource_kind::push_constant,
			.msl_buffer = 0,
			.name = "UniformBufferObject",
		}};
		source.metadata.inputs = {
			{.location = 0, .vector_size = 3},
			{.location = 1, .vector_size = 3},
			{.location = 2, .vector_size = 2},
		};
		source.metadata.outputs = {
			{.location = 0, .vector_size = 3},
			{.location = 1, .vector_size = 2},
		};
		return source;
	}

	shader_source make_fragment_source(const std::span<const std::uint32_t> words)
	{
		shader_source source;
		source.spirv = words;
		source.metadata.stage = shader_stage::fragment;
		source.metadata.policy.spirv_cross_revision = spirv_cross_revision;
		source.metadata.resources = {{
			.stage = shader_stage::fragment,
			.kind = resource_kind::combined_image_sampler,
			.descriptor_set = 0,
			.binding = 1,
			.msl_texture = 0,
			.msl_sampler = 0,
			.name = "texSampler",
		}};
		source.metadata.inputs = {
			{.location = 0, .vector_size = 3},
			{.location = 1, .vector_size = 2},
		};
		source.metadata.outputs = {{.location = 0, .vector_size = 4}};
		source.metadata.fragment_outputs = {{.location = 0, .components = 4}};
		return source;
	}

	void compile_msl(id<MTLDevice> device, const translated_shader& shader, const char* label)
	{
		NSString* source = [NSString stringWithUTF8String:shader.msl_source.c_str()];
		require(source != nil, std::string(label) + " generated invalid UTF-8 MSL");

		MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
		options.languageVersion = MTLLanguageVersion2_4;
		NSError* metal_error = nil;
		id<MTLLibrary> library = [device newLibraryWithSource:source options:options error:&metal_error];
		if (library == nil)
		{
			const char* detail = metal_error ? metal_error.localizedDescription.UTF8String : "unknown Metal error";
			fail(std::string(label) + " MSL compilation failed: " + detail);
		}

		NSString* entry_point = [NSString stringWithUTF8String:shader.msl_entry_point.c_str()];
		id<MTLFunction> function = [library newFunctionWithName:entry_point];
		require(function != nil, std::string(label) + " Metal entry point was not found");
	}
}

int main(const int argc, const char* argv[])
{
	@autoreleasepool
	{
		require(argc == 3, "expected vertex and fragment SPIR-V paths");
		const std::vector<std::uint32_t> vertex_words = load_spirv(argv[1]);
		const std::vector<std::uint32_t> fragment_words = load_spirv(argv[2]);

		const shader_source vertex_source = make_vertex_source(vertex_words);
		const shader_source fragment_source = make_fragment_source(fragment_words);
		const translation_result vertex = translate_spirv_to_msl(vertex_source);
		const translation_result fragment = translate_spirv_to_msl(fragment_source);
		require(static_cast<bool>(vertex), "vertex translation failed: " + vertex.error);
		require(static_cast<bool>(fragment), "fragment translation failed: " + fragment.error);
		require(vertex.shader->msl_source.find("vertex") != std::string::npos,
			"vertex translation did not emit a Metal vertex function");
		require(fragment.shader->msl_source.find("fragment") != std::string::npos,
			"fragment translation did not emit a Metal fragment function");
		require(vertex.shader->resources.size() == 1 && vertex.shader->resources[0].active,
			"vertex push-constant binding was not active");
		require(fragment.shader->resources.size() == 1 && fragment.shader->resources[0].active,
			"fragment texture/sampler binding was not active");

		const translation_result vertex_repeat = translate_spirv_to_msl(vertex_source);
		require(static_cast<bool>(vertex_repeat), "repeat vertex translation failed: " + vertex_repeat.error);
		require(vertex_repeat.shader->cache_key == vertex.shader->cache_key &&
			vertex_repeat.shader->msl_source == vertex.shader->msl_source,
			"identical SPIR-V did not produce deterministic MSL and cache identity");

		shader_source missing_binding = fragment_source;
		missing_binding.metadata.resources.clear();
		const translation_result rejected = translate_spirv_to_msl(missing_binding);
		require(!rejected && rejected.error.find("missing explicit binding metadata") != std::string::npos,
			"active SPIR-V resource without explicit Metal metadata did not fail closed");

		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		require(device != nil, "host has no Metal device");
		compile_msl(device, *vertex.shader, "vertex");
		compile_msl(device, *fragment.shader, "fragment");

		std::cout << "MTL SPIR-V translation tests passed: vertex="
			<< vertex.shader->cache_key.hex() << " fragment="
			<< fragment.shader->cache_key.hex() << '\n';
	}
	return 0;
}
