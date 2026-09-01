#include "MTLSpirvCompiler.h"

#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>

#include <algorithm>
#include <set>
#include <string_view>

#ifndef SPIRV_CROSS_NAMESPACE_OVERRIDE
#error "The MoltenVK converter bridge requires its exact pinned SPIRV-Cross namespace"
#endif

namespace rsx::mtl
{
	namespace spirv_cross = ::SPIRV_CROSS_NAMESPACE;

	namespace
	{
		spv::ExecutionModel execution_model(const shader_stage stage)
		{
			switch (stage)
			{
			case shader_stage::vertex:
				return spv::ExecutionModelVertex;
			case shader_stage::fragment:
				return spv::ExecutionModelFragment;
			case shader_stage::compute:
				return spv::ExecutionModelGLCompute;
			}
			return spv::ExecutionModelMax;
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
			result.builtin = source.builtin == invalid_binding ? spv::BuiltInMax : static_cast<spv::BuiltIn>(source.builtin);
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

		std::string unsupported_configuration(const shader_source& source)
		{
			for (const resource_binding& resource : source.metadata.resources)
			{
				if (resource.inline_uniform_block)
				{
					return "MoltenVK converter bridge does not support inline uniform blocks";
				}
				if (resource.argument_buffer_device_storage)
				{
					return "MoltenVK converter bridge does not expose argument-buffer device storage configuration";
				}
			}
			if (std::any_of(source.metadata.fragment_outputs.begin(), source.metadata.fragment_outputs.end(),
					[](const fragment_output_components& output)
					{
						return output.components != 4;
					}))
			{
				return "MoltenVK converter bridge cannot override fragment output component counts";
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
		if (result.error = unsupported_configuration(source); !result.error.empty())
		{
			return result;
		}

		const spv::ExecutionModel model = execution_model(source.metadata.stage);
		mvk::SPIRVToMSLConversionConfiguration configuration;
		configuration.options.entryPointName = source.metadata.entry_point;
		configuration.options.entryPointStage = model;
		configuration.options.shouldFlipVertexY = false;
		configuration.options.shouldFixupClipSpace = false;

		const translation_policy& policy = source.metadata.policy;
		auto& options = configuration.options.mslOptions;
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

		configuration.shaderInputs.reserve(source.metadata.inputs.size());
		for (const interface_variable& input : source.metadata.inputs)
		{
			mvk::MSLShaderInterfaceVariable converted;
			converted.shaderVar = make_interface_variable(input);
			configuration.shaderInputs.push_back(std::move(converted));
		}
		configuration.shaderOutputs.reserve(source.metadata.outputs.size());
		for (const interface_variable& output : source.metadata.outputs)
		{
			mvk::MSLShaderInterfaceVariable converted;
			converted.shaderVar = make_interface_variable(output);
			configuration.shaderOutputs.push_back(std::move(converted));
		}

		std::set<std::uint32_t> discrete_sets;
		configuration.resourceBindings.reserve(source.metadata.resources.size());
		for (const resource_binding& resource : source.metadata.resources)
		{
			const auto [descriptor_set, binding] = spirv_binding(resource);
			mvk::MSLResourceBinding converted;
			auto& mapped = converted.resourceBinding;
			mapped.stage = model;
			mapped.basetype = resource_base_type(resource.kind);
			mapped.desc_set = descriptor_set;
			mapped.binding = binding;
			mapped.count = resource.array_count;
			mapped.msl_buffer = resource.msl_buffer == invalid_binding ? 0 : resource.msl_buffer;
			mapped.msl_texture = resource.msl_texture == invalid_binding ? 0 : resource.msl_texture;
			mapped.msl_sampler = resource.msl_sampler == invalid_binding ? 0 : resource.msl_sampler;
			configuration.resourceBindings.push_back(std::move(converted));

			if (resource.dynamic_offset)
			{
				configuration.dynamicBufferDescriptors.push_back({model, descriptor_set, binding, resource.dynamic_offset_index});
			}
			if (resource.discrete_descriptor_set && discrete_sets.insert(descriptor_set).second)
			{
				configuration.discreteDescriptorSets.push_back(descriptor_set);
			}
		}

		mvk::SPIRVToMSLConverter converter;
		converter.setSPIRV(source.spirv.data(), source.spirv.size());
		mvk::SPIRVToMSLConversionResult conversion;
		if (!converter.convert(configuration, conversion, false, false, false) || conversion.msl.empty())
		{
			result.error = conversion.resultLog.empty() ? "MoltenVK failed to convert SPIR-V to MSL" : std::move(conversion.resultLog);
			return result;
		}

		translated_shader translated;
		translated.cache_key = make_shader_cache_key(source);
		translated.metadata = source.metadata;
		translated.msl_source = std::move(conversion.msl);
		translated.msl_entry_point = std::move(conversion.resultInfo.entryPoint.mtlFunctionName);
		if (translated.msl_entry_point.empty())
		{
			result.error = "MoltenVK produced no Metal shader entry point";
			return result;
		}

		translated.resources.reserve(source.metadata.resources.size());
		for (std::size_t index = 0; index < source.metadata.resources.size(); ++index)
		{
			translated.resources.push_back({source.metadata.resources[index], configuration.resourceBindings[index].outIsUsedByShader});
		}
		translated.inputs.reserve(source.metadata.inputs.size());
		for (std::size_t index = 0; index < source.metadata.inputs.size(); ++index)
		{
			translated.inputs.push_back({source.metadata.inputs[index], configuration.shaderInputs[index].outIsUsedByShader});
		}
		translated.outputs.reserve(source.metadata.outputs.size());
		for (std::size_t index = 0; index < source.metadata.outputs.size(); ++index)
		{
			translated.outputs.push_back({source.metadata.outputs[index], configuration.shaderOutputs[index].outIsUsedByShader});
		}
		translated.requirements.needs_swizzle_buffer = conversion.resultInfo.needsSwizzleBuffer;
		translated.requirements.needs_buffer_size_buffer = conversion.resultInfo.needsBufferSizeBuffer;
		translated.requirements.needs_output_buffer = conversion.resultInfo.needsOutputBuffer;
		translated.requirements.needs_patch_output_buffer = conversion.resultInfo.needsPatchOutputBuffer;
		translated.requirements.needs_input_threadgroup_memory = conversion.resultInfo.needsInputThreadgroupMem;
		translated.requirements.needs_dynamic_offset_buffer = conversion.resultInfo.needsDynamicOffsetBuffer;
		translated.requirements.rasterization_disabled = conversion.resultInfo.isRasterizationDisabled;
		result.shader = std::move(translated);
		return result;
	}
} // namespace rsx::mtl
