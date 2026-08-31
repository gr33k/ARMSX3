#include "stdafx.h"

#include "MTLRSXShaderProgram.h"

#include "../Program/GLSLTypes.h"
#include "../Program/SPIRVCommon.h"
#include "../VK/VKFragmentProgram.h"
#include "../VK/VKVertexProgram.h"

#include <algorithm>
#include <array>
#include <limits>
#include <span>

namespace rsx::mtl
{
	namespace
	{
		constexpr std::uint32_t max_metal_resource_index = 30;

		class binding_allocator
		{
		public:
			explicit binding_allocator(const translation_policy& policy)
			{
				m_blocked_buffers[policy.swizzle_buffer_index] = true;
				m_blocked_buffers[policy.indirect_params_buffer_index] = true;
				m_blocked_buffers[policy.shader_output_buffer_index] = true;
				m_blocked_buffers[policy.buffer_size_buffer_index] = true;
				m_blocked_buffers[policy.dynamic_offsets_buffer_index] = true;
			}

			std::optional<std::uint32_t> buffer(const std::uint32_t preferred)
			{
				return allocate(m_buffers, preferred, m_blocked_buffers);
			}

			std::optional<std::uint32_t> texture(const std::uint32_t preferred)
			{
				return allocate(m_textures, preferred, {});
			}

			std::optional<std::uint32_t> sampler(const std::uint32_t preferred)
			{
				return allocate(m_samplers, preferred, {});
			}

		private:
			using slot_map = std::array<bool, max_metal_resource_index + 1>;

			static std::optional<std::uint32_t> allocate(
				slot_map& used,
				const std::uint32_t preferred,
				const slot_map& blocked)
			{
				if (preferred <= max_metal_resource_index && !used[preferred] && !blocked[preferred])
				{
					used[preferred] = true;
					return preferred;
				}

				for (std::uint32_t index = 0; index <= max_metal_resource_index; ++index)
				{
					if (!used[index] && !blocked[index])
					{
						used[index] = true;
						return index;
					}
				}
				return std::nullopt;
			}

			slot_map m_buffers{};
			slot_map m_textures{};
			slot_map m_samplers{};
			slot_map m_blocked_buffers{};
		};

		translation_policy native_translation_policy()
		{
			translation_policy policy;
			policy.spirv_cross_revision = pinned_spirv_cross_revision;
			return policy;
		}

		bool assign_resource_slots(
			resource_binding& output,
			binding_allocator& allocator,
			const std::uint32_t preferred,
			std::string& error)
		{
			auto require = [&error](const std::optional<std::uint32_t> value, const char* resource_class)
			{
				if (!value)
				{
					error = std::string("Metal ") + resource_class + " binding space is exhausted";
					return invalid_binding;
				}
				return *value;
			};

			switch (output.kind)
			{
			case resource_kind::uniform_buffer:
			case resource_kind::storage_buffer:
			case resource_kind::push_constant:
				output.msl_buffer = require(allocator.buffer(preferred), "buffer");
				break;
			case resource_kind::texel_buffer:
			case resource_kind::sampled_texture:
			case resource_kind::storage_texture:
			case resource_kind::input_attachment:
				output.msl_texture = require(allocator.texture(preferred), "texture");
				break;
			case resource_kind::sampler:
				output.msl_sampler = require(allocator.sampler(preferred), "sampler");
				break;
			case resource_kind::combined_image_sampler:
				output.msl_texture = require(allocator.texture(preferred), "texture");
				if (error.empty())
				{
					output.msl_sampler = require(allocator.sampler(preferred), "sampler");
				}
				break;
			}

			return error.empty();
		}

		std::optional<resource_kind> resource_kind_for(const vk::glsl::program_input_type type)
		{
			switch (type)
			{
			case vk::glsl::input_type_uniform_buffer:
				return resource_kind::uniform_buffer;
			case vk::glsl::input_type_texel_buffer:
				return resource_kind::texel_buffer;
			case vk::glsl::input_type_texture:
				return resource_kind::combined_image_sampler;
			case vk::glsl::input_type_storage_buffer:
				return resource_kind::storage_buffer;
			case vk::glsl::input_type_storage_texture:
				return resource_kind::storage_texture;
			case vk::glsl::input_type_push_constant:
				return resource_kind::push_constant;
			case vk::glsl::input_type_max_enum:
			case vk::glsl::input_type_undefined:
				return std::nullopt;
			}
			return std::nullopt;
		}

		std::optional<shader_metadata> make_metadata(
			const shader_stage stage,
			const std::span<const vk::glsl::program_input> inputs,
			std::string& error)
		{
			shader_metadata metadata;
			metadata.stage = stage;
			metadata.policy = native_translation_policy();
			binding_allocator allocator(metadata.policy);
			metadata.resources.reserve(inputs.size());

			for (const vk::glsl::program_input& input : inputs)
			{
				const std::optional<resource_kind> kind = resource_kind_for(input.type);
				if (!kind)
				{
					error = "RSX decompiler emitted an unsupported resource class for " + input.name;
					return std::nullopt;
				}

				resource_binding resource;
				resource.stage = stage;
				resource.kind = *kind;
				resource.access = *kind == resource_kind::storage_texture ? resource_access::read_write : resource_access::read_only;
				resource.descriptor_set = input.set;
				resource.binding = input.type == vk::glsl::input_type_push_constant ? 0 : input.location;
				resource.name = input.name;

				const std::uint32_t preferred = input.location == std::numeric_limits<std::uint32_t>::max() ? max_metal_resource_index + 1 : input.location;
				if (!assign_resource_slots(resource, allocator, preferred, error))
				{
					return std::nullopt;
				}
				metadata.resources.push_back(std::move(resource));
			}

			return metadata;
		}

		bool compile_glsl(
			rsx_shader_program& output,
			const ::glsl::program_domain domain,
			std::string& error)
		{
			if (!spirv::compile_glsl_to_spv(
					output.spirv,
					output.glsl_source,
					domain,
					::glsl::glsl_rules_vulkan))
			{
				error = domain == ::glsl::glsl_vertex_program ? "glslang failed to compile the RSX vertex shader to SPIR-V" : "glslang failed to compile the RSX fragment shader to SPIR-V";
				return false;
			}

			if (error = validate_shader_source(output.source()); !error.empty())
			{
				error = "Metal shader metadata validation failed: " + error;
				return false;
			}
			return true;
		}
	} // namespace

	shader_source rsx_shader_program::source() const
	{
		return {
			.spirv = std::span<const std::uint32_t>(spirv),
			.metadata = metadata,
		};
	}

	rsx_shader_compile_result compile_vertex_program_to_spirv(
		const RSXVertexProgram& program,
		const rsx_shader_capabilities& capabilities)
	{
		rsx_shader_compile_result result;
		VKVertexProgram decompiled;
		decompiled.Decompile(program, {
										  .emulate_conditional_rendering = capabilities.emulate_conditional_rendering,
										  .emulate_depth_clip_only = capabilities.emulate_depth_clip_only,
										  .low_precision_tests = capabilities.low_precision_tests,
										  .require_explicit_invariance = capabilities.require_explicit_invariance,
									  });

		rsx_shader_program output;
		output.glsl_source = decompiled.shader.get_source();
		output.vertex_constant_ids = decompiled.constant_ids;
		output.vertex_has_indexed_constants = decompiled.has_indexed_constants;
		output.use_last_provoking_vertex = decompiled.use_last_provoking_vertex;

		const std::optional<shader_metadata> metadata = make_metadata(
			shader_stage::vertex,
			decompiled.uniforms,
			result.error);
		if (!metadata)
		{
			return result;
		}
		output.metadata = *metadata;
		if (!compile_glsl(output, ::glsl::glsl_vertex_program, result.error))
		{
			return result;
		}

		result.program = std::move(output);
		return result;
	}

	rsx_shader_compile_result compile_fragment_program_to_spirv(
		const RSXFragmentProgram& program,
		const rsx_shader_capabilities& capabilities)
	{
		rsx_shader_compile_result result;
		VKFragmentProgram decompiled;
		decompiled.Decompile(program, {
										  .has_native_half_support = capabilities.native_fragment_half,
										  .emulate_depth_compare = capabilities.emulate_depth_compare,
										  .has_low_precision_rounding = capabilities.low_precision_tests,
										  .disable_early_discard = capabilities.disable_early_discard,
									  });

		rsx_shader_program output;
		output.glsl_source = decompiled.shader.get_source();
		output.fragment_constant_offsets = decompiled.constant_offsets;
		output.fragment_output_color_masks = decompiled.output_color_masks;

		const std::optional<shader_metadata> metadata = make_metadata(
			shader_stage::fragment,
			decompiled.uniforms,
			result.error);
		if (!metadata)
		{
			return result;
		}
		output.metadata = *metadata;
		if (!compile_glsl(output, ::glsl::glsl_fragment_program, result.error))
		{
			return result;
		}

		result.program = std::move(output);
		return result;
	}
} // namespace rsx::mtl
