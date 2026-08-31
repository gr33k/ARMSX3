#include "MTLSpirvCompiler.h"

#include <spirv_msl.hpp>

#include <algorithm>
#include <exception>
#include <set>
#include <string_view>
#include <utility>

namespace rsx::mtl
{
#ifdef SPIRV_CROSS_NAMESPACE_OVERRIDE
	namespace spirv_cross = ::SPIRV_CROSS_NAMESPACE;
#endif

	namespace
	{
		spirv_cross::ExecutionModel execution_model(const shader_stage stage)
		{
			switch (stage)
			{
			case shader_stage::vertex:
				return spirv_cross::ExecutionModelVertex;
			case shader_stage::fragment:
				return spirv_cross::ExecutionModelFragment;
			case shader_stage::compute:
				return spirv_cross::ExecutionModelGLCompute;
			}
			return spirv_cross::ExecutionModelMax;
		}

		spirv_cross::SPIRType::BaseType resource_base_type(const resource_kind kind)
		{
			switch (kind)
			{
			case resource_kind::uniform_buffer:
			case resource_kind::storage_buffer:
			case resource_kind::push_constant:
				return spirv_cross::SPIRType::Struct;
			case resource_kind::texel_buffer:
			case resource_kind::storage_texture:
			case resource_kind::input_attachment:
				return spirv_cross::SPIRType::Image;
			case resource_kind::sampled_texture:
			case resource_kind::combined_image_sampler:
				return spirv_cross::SPIRType::SampledImage;
			case resource_kind::sampler:
				return spirv_cross::SPIRType::Sampler;
			}
			return spirv_cross::SPIRType::Unknown;
		}

		spirv_cross::MSLShaderVariableFormat variable_format(const interface_format format)
		{
			switch (format)
			{
			case interface_format::preserve:
				return spirv_cross::MSL_SHADER_VARIABLE_FORMAT_OTHER;
			case interface_format::uint8:
				return spirv_cross::MSL_SHADER_VARIABLE_FORMAT_UINT8;
			case interface_format::uint16:
				return spirv_cross::MSL_SHADER_VARIABLE_FORMAT_UINT16;
			case interface_format::any16:
				return spirv_cross::MSL_SHADER_VARIABLE_FORMAT_ANY16;
			case interface_format::any32:
				return spirv_cross::MSL_SHADER_VARIABLE_FORMAT_ANY32;
			}
			return spirv_cross::MSL_SHADER_VARIABLE_FORMAT_OTHER;
		}

		spirv_cross::MSLShaderVariableRate variable_rate(const interface_rate rate)
		{
			switch (rate)
			{
			case interface_rate::per_vertex:
				return spirv_cross::MSL_SHADER_VARIABLE_RATE_PER_VERTEX;
			case interface_rate::per_primitive:
				return spirv_cross::MSL_SHADER_VARIABLE_RATE_PER_PRIMITIVE;
			case interface_rate::per_patch:
				return spirv_cross::MSL_SHADER_VARIABLE_RATE_PER_PATCH;
			}
			return spirv_cross::MSL_SHADER_VARIABLE_RATE_PER_VERTEX;
		}

		spirv_cross::MSLShaderInterfaceVariable make_interface_variable(const interface_variable& source)
		{
			spirv_cross::MSLShaderInterfaceVariable result;
			result.location = source.location;
			result.component = source.component;
			result.format = variable_format(source.format);
			result.builtin = source.builtin == invalid_binding ? spirv_cross::BuiltInMax : static_cast<spirv_cross::BuiltIn>(source.builtin);
			result.vecsize = source.vector_size;
			result.rate = variable_rate(source.rate);
			return result;
		}

		std::pair<std::uint32_t, std::uint32_t> spirv_binding(const resource_binding& resource)
		{
			if (resource.kind == resource_kind::push_constant)
			{
				return {spirv_cross::kPushConstDescSet, spirv_cross::kPushConstBinding};
			}
			return {resource.descriptor_set, resource.binding};
		}

		const resource_binding* find_resource_binding(
			const shader_metadata& metadata,
			const std::uint32_t descriptor_set,
			const std::uint32_t binding)
		{
			const auto iterator = std::find_if(metadata.resources.begin(), metadata.resources.end(),
				[descriptor_set, binding](const resource_binding& resource)
				{
					return resource.kind != resource_kind::push_constant &&
				           resource.descriptor_set == descriptor_set && resource.binding == binding;
				});
			return iterator == metadata.resources.end() ? nullptr : &*iterator;
		}

		const resource_binding* find_push_constant(const shader_metadata& metadata)
		{
			const auto iterator = std::find_if(metadata.resources.begin(), metadata.resources.end(),
				[](const resource_binding& resource)
				{
					return resource.kind == resource_kind::push_constant;
				});
			return iterator == metadata.resources.end() ? nullptr : &*iterator;
		}

		bool is_texel_buffer(spirv_cross::CompilerMSL& compiler, const spirv_cross::Resource& resource)
		{
			return compiler.get_type(resource.type_id).image.dim == spirv_cross::DimBuffer;
		}

		std::string validate_reflected_resources(spirv_cross::CompilerMSL& compiler, const shader_metadata& metadata)
		{
			const auto active_variables = compiler.get_active_interface_variables();
			const spirv_cross::ShaderResources reflected = compiler.get_shader_resources(active_variables);

			auto require_bindings = [&compiler, &metadata](
										const auto& resources,
										const std::string_view category,
										auto&& kind_is_compatible) -> std::string
			{
				for (const spirv_cross::Resource& reflected_resource : resources)
				{
					if (!compiler.has_decoration(reflected_resource.id, spirv_cross::DecorationDescriptorSet) ||
						!compiler.has_decoration(reflected_resource.id, spirv_cross::DecorationBinding))
					{
						return "Active " + std::string(category) + " resource has no SPIR-V descriptor set/binding";
					}
					const std::uint32_t descriptor_set = compiler.get_decoration(reflected_resource.id, spirv_cross::DecorationDescriptorSet);
					const std::uint32_t binding = compiler.get_decoration(reflected_resource.id, spirv_cross::DecorationBinding);
					const resource_binding* supplied = find_resource_binding(metadata, descriptor_set, binding);
					if (!supplied)
					{
						return "Active " + std::string(category) + " resource is missing explicit binding metadata at set " +
						       std::to_string(descriptor_set) + ", binding " + std::to_string(binding);
					}
					if (!kind_is_compatible(*supplied, reflected_resource))
					{
						return "Active " + std::string(category) + " resource has incompatible binding metadata at set " +
						       std::to_string(descriptor_set) + ", binding " + std::to_string(binding);
					}
				}
				return {};
			};

			const auto exact_kind = [](const resource_kind expected)
			{
				return [expected](const resource_binding& supplied, const spirv_cross::Resource&)
				{
					return supplied.kind == expected;
				};
			};
			const auto image_kind = [&compiler](const resource_kind expected)
			{
				return [&compiler, expected](const resource_binding& supplied, const spirv_cross::Resource& resource)
				{
					return supplied.kind == expected ||
					       (supplied.kind == resource_kind::texel_buffer && is_texel_buffer(compiler, resource));
				};
			};

			if (std::string error = require_bindings(reflected.uniform_buffers, "uniform-buffer", exact_kind(resource_kind::uniform_buffer)); !error.empty())
				return error;
			if (std::string error = require_bindings(reflected.storage_buffers, "storage-buffer", exact_kind(resource_kind::storage_buffer)); !error.empty())
				return error;
			if (std::string error = require_bindings(reflected.subpass_inputs, "input-attachment", exact_kind(resource_kind::input_attachment)); !error.empty())
				return error;
			if (std::string error = require_bindings(reflected.storage_images, "storage-image", image_kind(resource_kind::storage_texture)); !error.empty())
				return error;
			if (std::string error = require_bindings(reflected.sampled_images, "combined-image-sampler", image_kind(resource_kind::combined_image_sampler)); !error.empty())
				return error;
			if (std::string error = require_bindings(reflected.separate_images, "separate-image", image_kind(resource_kind::sampled_texture)); !error.empty())
				return error;
			if (std::string error = require_bindings(reflected.separate_samplers, "separate-sampler", exact_kind(resource_kind::sampler)); !error.empty())
				return error;

			if (!reflected.push_constant_buffers.empty() && !find_push_constant(metadata))
			{
				return "Active push-constant block is missing explicit Metal buffer metadata";
			}
			if (!reflected.atomic_counters.empty() || !reflected.acceleration_structures.empty() ||
				!reflected.shader_record_buffers.empty() || !reflected.gl_plain_uniforms.empty() || !reflected.tensors.empty())
			{
				return "SPIR-V contains a resource class unsupported by the iOS RSX Metal slice";
			}
			return {};
		}
	} // namespace

	translation_result translate_spirv_to_msl(const shader_source& source) noexcept
	{
		translation_result result;
		if (result.error = validate_shader_source(source); !result.error.empty())
		{
			return result;
		}

		try
		{
			const spirv_cross::ExecutionModel model = execution_model(source.metadata.stage);
			spirv_cross::CompilerMSL compiler(source.spirv.data(), source.spirv.size());
			compiler.set_entry_point(source.metadata.entry_point, model);
			if (result.error = validate_reflected_resources(compiler, source.metadata); !result.error.empty())
			{
				return result;
			}

			const translation_policy& policy = source.metadata.policy;
			auto options = compiler.get_msl_options();
			options.platform = spirv_cross::CompilerMSL::Options::iOS;
			options.set_msl_version(policy.msl_major, policy.msl_minor, policy.msl_patch);
			options.invariant_float_math = policy.invariant_float_math;
			options.ios_support_base_vertex_instance = policy.ios_support_base_vertex_instance;
			options.enable_base_index_zero = policy.enable_base_index_zero;
			options.pad_fragment_output_components = policy.pad_fragment_output_components;
			options.texture_buffer_native = policy.texture_buffer_native;
			options.argument_buffers = policy.argument_buffers;
			options.argument_buffers_tier = policy.argument_buffer_tier == 2 ? spirv_cross::CompilerMSL::Options::ArgumentBuffersTier::Tier2 : spirv_cross::CompilerMSL::Options::ArgumentBuffersTier::Tier1;
			options.force_active_argument_buffer_resources = policy.force_active_argument_buffer_resources;
			options.pad_argument_buffer_resources = policy.pad_argument_buffer_resources;
			options.swizzle_texture_samples = policy.swizzle_texture_samples;
			options.manual_helper_invocation_updates = policy.manual_helper_invocation_updates;
			options.readwrite_texture_fences = policy.readwrite_texture_fences;
			options.agx_manual_cube_grad_fixup = policy.agx_manual_cube_grad_fixup;
			options.force_fragment_with_side_effects_execution = policy.force_fragment_with_side_effects_execution;
			options.auto_disable_rasterization = policy.auto_disable_rasterization;
			options.enable_frag_output_mask = policy.enabled_fragment_output_mask;
			options.additional_fixed_sample_mask = policy.fixed_sample_mask;
			options.texel_buffer_texture_width = policy.texel_buffer_texture_width;
			options.swizzle_buffer_index = policy.swizzle_buffer_index;
			options.indirect_params_buffer_index = policy.indirect_params_buffer_index;
			options.shader_output_buffer_index = policy.shader_output_buffer_index;
			options.buffer_size_buffer_index = policy.buffer_size_buffer_index;
			options.dynamic_offsets_buffer_index = policy.dynamic_offsets_buffer_index;
			options.enable_decoration_binding = false;
			options.use_fast_math_pragmas = false;
			compiler.set_msl_options(options);

			// Vulkan and Metal both use a [0, 1] depth range. Do not alter positions or
			// SPIR-V precision decorations in this translation boundary.
			auto common_options = compiler.get_common_options();
			common_options.vertex.fixup_clipspace = false;
			common_options.vertex.flip_vert_y = false;
			compiler.set_common_options(common_options);

			std::set<std::uint32_t> discrete_sets;
			std::set<std::uint32_t> device_storage_sets;
			for (const resource_binding& resource : source.metadata.resources)
			{
				const auto [descriptor_set, binding] = spirv_binding(resource);
				spirv_cross::MSLResourceBinding remap;
				remap.stage = model;
				remap.basetype = resource_base_type(resource.kind);
				remap.desc_set = descriptor_set;
				remap.binding = binding;
				remap.count = resource.array_count;
				remap.msl_buffer = resource.msl_buffer == invalid_binding ? 0 : resource.msl_buffer;
				remap.msl_texture = resource.msl_texture == invalid_binding ? 0 : resource.msl_texture;
				remap.msl_sampler = resource.msl_sampler == invalid_binding ? 0 : resource.msl_sampler;
				compiler.add_msl_resource_binding(remap);

				if (resource.dynamic_offset)
				{
					compiler.add_dynamic_buffer(descriptor_set, binding, resource.dynamic_offset_index);
				}
				if (resource.inline_uniform_block)
				{
					compiler.add_inline_uniform_block(descriptor_set, binding);
				}
				if (resource.discrete_descriptor_set && discrete_sets.insert(descriptor_set).second)
				{
					compiler.add_discrete_descriptor_set(descriptor_set);
				}
				if (resource.argument_buffer_device_storage && device_storage_sets.insert(descriptor_set).second)
				{
					compiler.set_argument_buffer_device_address_space(descriptor_set, true);
				}
			}

			for (const interface_variable& input : source.metadata.inputs)
			{
				compiler.add_msl_shader_input(make_interface_variable(input));
			}
			for (const interface_variable& output : source.metadata.outputs)
			{
				compiler.add_msl_shader_output(make_interface_variable(output));
			}
			for (const fragment_output_components& output : source.metadata.fragment_outputs)
			{
				compiler.set_fragment_output_components(output.location, output.components);
			}

			translated_shader translated;
			translated.cache_key = make_shader_cache_key(source);
			translated.metadata = source.metadata;
			translated.msl_source = compiler.compile();
			translated.msl_entry_point = compiler.get_cleansed_entry_point_name(source.metadata.entry_point, model);

			translated.resources.reserve(source.metadata.resources.size());
			for (const resource_binding& resource : source.metadata.resources)
			{
				const auto [descriptor_set, binding] = spirv_binding(resource);
				translated.resources.push_back({
					.binding = resource,
					.active = compiler.is_msl_resource_binding_used(model, descriptor_set, binding),
				});
			}
			translated.inputs.reserve(source.metadata.inputs.size());
			for (const interface_variable& input : source.metadata.inputs)
			{
				translated.inputs.push_back({
					.variable = input,
					.active = compiler.is_msl_shader_input_used(input.location),
				});
			}
			translated.outputs.reserve(source.metadata.outputs.size());
			for (const interface_variable& output : source.metadata.outputs)
			{
				translated.outputs.push_back({
					.variable = output,
					.active = compiler.is_msl_shader_output_used(output.location),
				});
			}

			translated.requirements.needs_swizzle_buffer = compiler.needs_swizzle_buffer();
			translated.requirements.needs_buffer_size_buffer = compiler.needs_buffer_size_buffer();
			translated.requirements.needs_output_buffer = compiler.needs_output_buffer();
			translated.requirements.needs_patch_output_buffer = compiler.needs_patch_output_buffer();
			translated.requirements.needs_input_threadgroup_memory = compiler.needs_input_threadgroup_mem();
			translated.requirements.needs_dynamic_offset_buffer = policy.argument_buffers &&
			                                                      std::any_of(source.metadata.resources.begin(), source.metadata.resources.end(),
																	  [](const resource_binding& resource)
																	  {
																		  return resource.dynamic_offset;
																	  });
			translated.requirements.rasterization_disabled = compiler.get_is_rasterization_disabled();
			translated.requirements.writes_point_size = compiler.get_writes_to_point_size();
			result.shader = std::move(translated);
		}
		catch (const std::exception& exception)
		{
			result.error = exception.what();
		}
		catch (...)
		{
			result.error = "Unknown SPIRV-Cross failure";
		}
		return result;
	}
} // namespace rsx::mtl
