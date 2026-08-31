#include "../MTLShaderTypes.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <utility>

namespace
{
	using namespace rsx::mtl;

	void require(const bool condition, const char* message)
	{
		if (!condition)
		{
			std::cerr << "MTL shader key test failed: " << message << '\n';
			std::exit(1);
		}
	}

	shader_source make_shader(std::span<const std::uint32_t> words)
	{
		shader_source source;
		source.spirv = words;
		source.metadata.stage = shader_stage::vertex;
		source.metadata.policy.spirv_cross_revision = "test-revision-01234567";
		source.metadata.resources = {
			{
				.stage = shader_stage::vertex,
				.kind = resource_kind::uniform_buffer,
				.descriptor_set = 0,
				.binding = 0,
				.msl_buffer = 0,
				.name = "VertexContextBuffer",
			},
			{
				.stage = shader_stage::vertex,
				.kind = resource_kind::combined_image_sampler,
				.descriptor_set = 0,
				.binding = 1,
				.msl_texture = 0,
				.msl_sampler = 0,
				.name = "vtex0",
			},
		};
		source.metadata.inputs = {{.location = 0, .vector_size = 4}};
		return source;
	}
} // namespace

int main()
{
	std::array<std::uint32_t, 6> words = {0x07230203, 0x00010500, 0, 8, 0, 0x12345678};
	shader_source source = make_shader(words);
	require(validate_shader_source(source).empty(), "baseline metadata must validate");

	const stable_digest baseline = make_shader_cache_key(source);
	require(baseline.hex() == "1f2f18f1ac03a9a9e0b7607d96b272783d378160ea3dde7f22f1abc3b75243e9",
		"canonical shader key changed without a schema-version update");
	shader_source reordered = source;
	std::swap(reordered.metadata.resources[0], reordered.metadata.resources[1]);
	require(make_shader_cache_key(reordered) == baseline, "resource ordering must not perturb the key");

	shader_source changed_binding = source;
	changed_binding.metadata.resources[1].msl_texture = 1;
	require(make_shader_cache_key(changed_binding) != baseline, "Metal resource remaps must affect the key");

	words.back() ^= 1;
	require(make_shader_cache_key(source) != baseline, "SPIR-V words must affect the key");
	words.back() ^= 1;

	shader_source duplicate = source;
	duplicate.metadata.resources.push_back(duplicate.metadata.resources.front());
	require(!validate_shader_source(duplicate).empty(), "duplicate descriptor bindings must fail closed");
	shader_source unpinned = source;
	unpinned.metadata.policy.spirv_cross_revision.clear();
	require(!validate_shader_source(unpinned).empty(), "an unpinned translator revision must fail closed");
	shader_source oversized_array = source;
	oversized_array.metadata.resources[0].array_count = 32;
	require(!validate_shader_source(oversized_array).empty(), "oversized Metal binding arrays must fail closed");
	shader_source changed_constant = source;
	changed_constant.metadata.function_constants = {{.index = 7, .type = function_constant_type::boolean, .value = {1}, .value_size = 1}};
	require(make_shader_cache_key(changed_constant) != baseline, "function constants must affect the shader key");

	render_pipeline_metadata pipeline;
	pipeline.color_attachments = {{.pixel_format = 80}};
	pipeline.vertex_attributes = {
		{.attribute_index = 2, .format = 30, .offset = 16, .buffer_index = 0},
		{.attribute_index = 0, .format = 30, .offset = 0, .buffer_index = 0},
	};
	pipeline.vertex_layouts = {{.buffer_index = 0, .stride = 32}};
	const stable_digest pipeline_key = make_render_pipeline_cache_key(baseline, baseline, pipeline);
	std::swap(pipeline.vertex_attributes[0], pipeline.vertex_attributes[1]);
	require(make_render_pipeline_cache_key(baseline, baseline, pipeline) == pipeline_key,
		"vertex attribute ordering must not perturb the key");
	pipeline.sample_count = 4;
	require(make_render_pipeline_cache_key(baseline, baseline, pipeline) != pipeline_key,
		"sample count must affect the pipeline key");

	render_pipeline_source render_source;
	render_source.vertex = source;
	render_source.fragment = source;
	render_source.fragment.metadata.stage = shader_stage::fragment;
	for (resource_binding& resource : render_source.fragment.metadata.resources)
	{
		resource.stage = shader_stage::fragment;
	}
	render_source.pipeline = pipeline;
	require(validate_render_pipeline_source(render_source).empty(), "baseline render-pipeline metadata must validate");
	render_source.pipeline.color_attachments.resize(9);
	require(!validate_render_pipeline_source(render_source).empty(), "more than eight color attachments must fail closed");

	std::cout << "MTL shader key tests passed: " << baseline.hex() << '\n';
	return 0;
}
