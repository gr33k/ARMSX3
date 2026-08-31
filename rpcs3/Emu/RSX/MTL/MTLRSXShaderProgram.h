#pragma once

#include "MTLShaderTypes.h"

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

struct RSXFragmentProgram;
struct RSXVertexProgram;

namespace rsx::mtl
{
	inline constexpr const char* pinned_spirv_cross_revision = "6c09849fe88c48eaed08413aa022aaa136a3a057";

	struct rsx_shader_capabilities
	{
		bool emulate_conditional_rendering = true;
		bool emulate_depth_clip_only = false;
		bool low_precision_tests = false;
		bool require_explicit_invariance = true;
		bool native_fragment_half = false;
		bool emulate_depth_compare = false;
		bool disable_early_discard = true;
	};

	struct rsx_shader_program
	{
		std::string glsl_source;
		std::vector<std::uint32_t> spirv;
		shader_metadata metadata;
		std::vector<std::uint16_t> vertex_constant_ids;
		std::vector<std::uint32_t> fragment_constant_offsets;
		std::array<std::uint32_t, 4> fragment_output_color_masks{};
		bool vertex_has_indexed_constants = false;
		bool use_last_provoking_vertex = false;

		[[nodiscard]] shader_source source() const;
	};

	struct rsx_shader_compile_result
	{
		std::optional<rsx_shader_program> program;
		std::string error;

		[[nodiscard]] explicit operator bool() const noexcept
		{
			return program.has_value();
		}
	};

	// glslang must be initialized by the owning renderer before either function is
	// called. These functions create no Vulkan device, shader module, or pipeline.
	[[nodiscard]] rsx_shader_compile_result compile_vertex_program_to_spirv(
		const RSXVertexProgram& program,
		const rsx_shader_capabilities& capabilities = {});
	[[nodiscard]] rsx_shader_compile_result compile_fragment_program_to_spirv(
		const RSXFragmentProgram& program,
		const rsx_shader_capabilities& capabilities = {});
} // namespace rsx::mtl
