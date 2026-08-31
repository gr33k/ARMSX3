#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace rsx::mtl
{
	inline constexpr std::uint32_t invalid_binding = UINT32_MAX;
	inline constexpr std::uint32_t shader_key_schema_version = 1;
	inline constexpr std::uint32_t pipeline_key_schema_version = 1;

	enum class shader_stage : std::uint8_t
	{
		vertex,
		fragment,
		compute,
	};

	enum class resource_kind : std::uint8_t
	{
		uniform_buffer,
		storage_buffer,
		texel_buffer,
		sampled_texture,
		storage_texture,
		sampler,
		combined_image_sampler,
		input_attachment,
		push_constant,
	};

	enum class resource_access : std::uint8_t
	{
		read_only,
		write_only,
		read_write,
	};

	enum class interface_format : std::uint8_t
	{
		preserve,
		uint8,
		uint16,
		any16,
		any32,
	};

	enum class interface_rate : std::uint8_t
	{
		per_vertex,
		per_primitive,
		per_patch,
	};

	enum class precision_policy : std::uint8_t
	{
		preserve_spirv,
	};

	enum class function_constant_type : std::uint8_t
	{
		boolean,
		int8,
		uint8,
		int16,
		uint16,
		int32,
		uint32,
		float16,
		float32,
	};

	struct resource_binding
	{
		shader_stage stage = shader_stage::vertex;
		resource_kind kind = resource_kind::uniform_buffer;
		resource_access access = resource_access::read_only;
		std::uint32_t descriptor_set = 0;
		std::uint32_t binding = 0;
		std::uint32_t array_count = 1;
		std::uint32_t msl_buffer = invalid_binding;
		std::uint32_t msl_texture = invalid_binding;
		std::uint32_t msl_sampler = invalid_binding;
		bool dynamic_offset = false;
		std::uint32_t dynamic_offset_index = 0;
		bool inline_uniform_block = false;
		bool discrete_descriptor_set = false;
		bool argument_buffer_device_storage = false;
		std::string name;
	};

	struct interface_variable
	{
		std::uint32_t location = 0;
		std::uint32_t component = 0;
		interface_format format = interface_format::preserve;
		std::uint32_t builtin = invalid_binding;
		std::uint32_t vector_size = 0;
		interface_rate rate = interface_rate::per_vertex;
	};

	struct fragment_output_components
	{
		std::uint32_t location = 0;
		std::uint32_t components = 4;
	};

	struct function_constant
	{
		std::uint32_t index = 0;
		function_constant_type type = function_constant_type::uint32;
		std::array<std::uint8_t, 4> value{};
		std::uint8_t value_size = 4;
	};

	struct translation_policy
	{
		// The exact pinned SPIRV-Cross revision is mandatory because generated MSL can
		// change without any change to the SPIR-V or RSX metadata.
		std::string spirv_cross_revision;
		std::uint32_t msl_major = 2;
		std::uint32_t msl_minor = 4;
		std::uint32_t msl_patch = 0;
		precision_policy precision = precision_policy::preserve_spirv;
		bool preserve_invariance = true;
		bool invariant_float_math = true;
		bool ios_support_base_vertex_instance = true;
		bool enable_base_index_zero = false;
		bool pad_fragment_output_components = true;
		bool texture_buffer_native = true;
		bool argument_buffers = false;
		std::uint8_t argument_buffer_tier = 1;
		bool force_active_argument_buffer_resources = false;
		bool pad_argument_buffer_resources = false;
		bool swizzle_texture_samples = false;
		bool manual_helper_invocation_updates = true;
		bool readwrite_texture_fences = true;
		bool agx_manual_cube_grad_fixup = true;
		bool force_fragment_with_side_effects_execution = true;
		bool auto_disable_rasterization = true;
		std::uint32_t enabled_fragment_output_mask = UINT32_MAX;
		std::uint32_t fixed_sample_mask = UINT32_MAX;
		std::uint32_t texel_buffer_texture_width = 4096;
		std::uint32_t swizzle_buffer_index = 30;
		std::uint32_t indirect_params_buffer_index = 29;
		std::uint32_t shader_output_buffer_index = 28;
		std::uint32_t buffer_size_buffer_index = 25;
		std::uint32_t dynamic_offsets_buffer_index = 23;
	};

	struct shader_metadata
	{
		shader_stage stage = shader_stage::vertex;
		std::string entry_point = "main";
		translation_policy policy;
		std::vector<resource_binding> resources;
		std::vector<interface_variable> inputs;
		std::vector<interface_variable> outputs;
		std::vector<fragment_output_components> fragment_outputs;
		std::vector<function_constant> function_constants;
	};

	struct shader_source
	{
		std::span<const std::uint32_t> spirv;
		shader_metadata metadata;
	};

	// Raw enum values intentionally mirror Metal API enum values while keeping this
	// contract host-independent and free of Objective-C framework headers.
	struct color_attachment_state
	{
		std::uint64_t pixel_format = 0;
		bool blending_enabled = false;
		std::uint64_t source_rgb_blend_factor = 1;
		std::uint64_t destination_rgb_blend_factor = 0;
		std::uint64_t rgb_blend_operation = 0;
		std::uint64_t source_alpha_blend_factor = 1;
		std::uint64_t destination_alpha_blend_factor = 0;
		std::uint64_t alpha_blend_operation = 0;
		std::uint64_t write_mask = 0xf;
	};

	struct vertex_attribute_state
	{
		std::uint32_t attribute_index = 0;
		std::uint64_t format = 0;
		std::uint32_t offset = 0;
		std::uint32_t buffer_index = 0;
	};

	struct vertex_buffer_layout_state
	{
		std::uint32_t buffer_index = 0;
		std::uint32_t stride = 0;
		std::uint64_t step_function = 1;
		std::uint32_t step_rate = 1;
	};

	struct render_pipeline_metadata
	{
		std::vector<color_attachment_state> color_attachments;
		std::uint64_t depth_attachment_pixel_format = 0;
		std::uint64_t stencil_attachment_pixel_format = 0;
		std::uint32_t sample_count = 1;
		std::uint64_t input_primitive_topology = 0;
		bool alpha_to_coverage_enabled = false;
		bool alpha_to_one_enabled = false;
		bool rasterization_enabled = true;
		bool support_indirect_command_buffers = false;
		std::uint32_t max_vertex_amplification_count = 1;
		std::vector<vertex_attribute_state> vertex_attributes;
		std::vector<vertex_buffer_layout_state> vertex_layouts;
	};

	struct render_pipeline_source
	{
		shader_source vertex;
		shader_source fragment;
		render_pipeline_metadata pipeline;
		std::string label;
	};

	struct stable_digest
	{
		std::array<std::uint8_t, 32> bytes{};

		friend bool operator==(const stable_digest&, const stable_digest&) = default;
		[[nodiscard]] std::string hex() const;
	};

	struct stable_digest_hash
	{
		[[nodiscard]] std::size_t operator()(const stable_digest& digest) const noexcept;
	};

	[[nodiscard]] std::string validate_shader_source(const shader_source& source);
	[[nodiscard]] std::string validate_render_pipeline_source(const render_pipeline_source& source);
	[[nodiscard]] stable_digest make_shader_cache_key(const shader_source& source);
	[[nodiscard]] stable_digest make_render_pipeline_cache_key(
		const stable_digest& vertex_key,
		const stable_digest& fragment_key,
		const render_pipeline_metadata& metadata);
} // namespace rsx::mtl
