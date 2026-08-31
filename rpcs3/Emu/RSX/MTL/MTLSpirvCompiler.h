#pragma once

#include "MTLShaderTypes.h"

#include <optional>
#include <string>
#include <vector>

namespace rsx::mtl
{
	struct translated_resource_binding
	{
		resource_binding binding;
		bool active = false;
	};

	struct translated_interface_variable
	{
		interface_variable variable;
		bool active = false;
	};

	struct translation_requirements
	{
		bool needs_swizzle_buffer = false;
		bool needs_buffer_size_buffer = false;
		bool needs_output_buffer = false;
		bool needs_patch_output_buffer = false;
		bool needs_input_threadgroup_memory = false;
		bool needs_dynamic_offset_buffer = false;
		bool rasterization_disabled = false;
		bool writes_point_size = false;
	};

	struct translated_shader
	{
		stable_digest cache_key;
		shader_metadata metadata;
		std::string msl_source;
		std::string msl_entry_point;
		std::vector<translated_resource_binding> resources;
		std::vector<translated_interface_variable> inputs;
		std::vector<translated_interface_variable> outputs;
		translation_requirements requirements;
	};

	struct translation_result
	{
		std::optional<translated_shader> shader;
		std::string error;

		[[nodiscard]] explicit operator bool() const noexcept
		{
			return shader.has_value();
		}
	};

	// The caller supplies Vulkan-semantics SPIR-V produced by RPCS3/glslang and an
	// explicit RSX binding table. No resource index is inferred or renumbered here.
	[[nodiscard]] translation_result translate_spirv_to_msl(const shader_source& source) noexcept;
} // namespace rsx::mtl
