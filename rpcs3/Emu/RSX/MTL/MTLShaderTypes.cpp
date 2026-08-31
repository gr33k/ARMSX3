#include "MTLShaderTypes.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cstring>
#include <limits>
#include <set>
#include <sstream>
#include <tuple>
#include <utility>

namespace rsx::mtl
{
	namespace
	{
		constexpr std::uint32_t spirv_magic = 0x07230203;
		constexpr std::uint32_t max_metal_binding_index = 30;
		constexpr std::uint32_t max_color_attachments = 8;

		class sha256
		{
		public:
			sha256() = default;

			void update(const std::span<const std::uint8_t> input)
			{
				for (const std::uint8_t byte : input)
				{
					m_block[m_block_size++] = byte;
					if (m_block_size == m_block.size())
					{
						transform();
						m_bit_count += 512;
						m_block_size = 0;
					}
				}
			}

			stable_digest finish()
			{
				m_bit_count += static_cast<std::uint64_t>(m_block_size) * 8;
				m_block[m_block_size++] = 0x80;

				if (m_block_size > 56)
				{
					while (m_block_size < 64)
					{
						m_block[m_block_size++] = 0;
					}
					transform();
					m_block_size = 0;
				}

				while (m_block_size < 56)
				{
					m_block[m_block_size++] = 0;
				}

				for (int shift = 56; shift >= 0; shift -= 8)
				{
					m_block[m_block_size++] = static_cast<std::uint8_t>(m_bit_count >> shift);
				}
				transform();

				stable_digest result;
				for (std::size_t index = 0; index < m_state.size(); ++index)
				{
					result.bytes[index * 4] = static_cast<std::uint8_t>(m_state[index] >> 24);
					result.bytes[index * 4 + 1] = static_cast<std::uint8_t>(m_state[index] >> 16);
					result.bytes[index * 4 + 2] = static_cast<std::uint8_t>(m_state[index] >> 8);
					result.bytes[index * 4 + 3] = static_cast<std::uint8_t>(m_state[index]);
				}
				return result;
			}

		private:
			static constexpr std::array<std::uint32_t, 64> constants = {
				0x428a2f98,
				0x71374491,
				0xb5c0fbcf,
				0xe9b5dba5,
				0x3956c25b,
				0x59f111f1,
				0x923f82a4,
				0xab1c5ed5,
				0xd807aa98,
				0x12835b01,
				0x243185be,
				0x550c7dc3,
				0x72be5d74,
				0x80deb1fe,
				0x9bdc06a7,
				0xc19bf174,
				0xe49b69c1,
				0xefbe4786,
				0x0fc19dc6,
				0x240ca1cc,
				0x2de92c6f,
				0x4a7484aa,
				0x5cb0a9dc,
				0x76f988da,
				0x983e5152,
				0xa831c66d,
				0xb00327c8,
				0xbf597fc7,
				0xc6e00bf3,
				0xd5a79147,
				0x06ca6351,
				0x14292967,
				0x27b70a85,
				0x2e1b2138,
				0x4d2c6dfc,
				0x53380d13,
				0x650a7354,
				0x766a0abb,
				0x81c2c92e,
				0x92722c85,
				0xa2bfe8a1,
				0xa81a664b,
				0xc24b8b70,
				0xc76c51a3,
				0xd192e819,
				0xd6990624,
				0xf40e3585,
				0x106aa070,
				0x19a4c116,
				0x1e376c08,
				0x2748774c,
				0x34b0bcb5,
				0x391c0cb3,
				0x4ed8aa4a,
				0x5b9cca4f,
				0x682e6ff3,
				0x748f82ee,
				0x78a5636f,
				0x84c87814,
				0x8cc70208,
				0x90befffa,
				0xa4506ceb,
				0xbef9a3f7,
				0xc67178f2,
			};

			static std::uint32_t choose(const std::uint32_t x, const std::uint32_t y, const std::uint32_t z)
			{
				return (x & y) ^ (~x & z);
			}

			static std::uint32_t majority(const std::uint32_t x, const std::uint32_t y, const std::uint32_t z)
			{
				return (x & y) ^ (x & z) ^ (y & z);
			}

			void transform()
			{
				std::array<std::uint32_t, 64> words{};
				for (std::size_t index = 0; index < 16; ++index)
				{
					words[index] = (static_cast<std::uint32_t>(m_block[index * 4]) << 24) |
					               (static_cast<std::uint32_t>(m_block[index * 4 + 1]) << 16) |
					               (static_cast<std::uint32_t>(m_block[index * 4 + 2]) << 8) |
					               static_cast<std::uint32_t>(m_block[index * 4 + 3]);
				}
				for (std::size_t index = 16; index < words.size(); ++index)
				{
					const std::uint32_t s0 = std::rotr(words[index - 15], 7) ^ std::rotr(words[index - 15], 18) ^ (words[index - 15] >> 3);
					const std::uint32_t s1 = std::rotr(words[index - 2], 17) ^ std::rotr(words[index - 2], 19) ^ (words[index - 2] >> 10);
					words[index] = words[index - 16] + s0 + words[index - 7] + s1;
				}

				std::uint32_t a = m_state[0];
				std::uint32_t b = m_state[1];
				std::uint32_t c = m_state[2];
				std::uint32_t d = m_state[3];
				std::uint32_t e = m_state[4];
				std::uint32_t f = m_state[5];
				std::uint32_t g = m_state[6];
				std::uint32_t h = m_state[7];

				for (std::size_t index = 0; index < words.size(); ++index)
				{
					const std::uint32_t sum1 = std::rotr(e, 6) ^ std::rotr(e, 11) ^ std::rotr(e, 25);
					const std::uint32_t temp1 = h + sum1 + choose(e, f, g) + constants[index] + words[index];
					const std::uint32_t sum0 = std::rotr(a, 2) ^ std::rotr(a, 13) ^ std::rotr(a, 22);
					const std::uint32_t temp2 = sum0 + majority(a, b, c);
					h = g;
					g = f;
					f = e;
					e = d + temp1;
					d = c;
					c = b;
					b = a;
					a = temp1 + temp2;
				}

				m_state[0] += a;
				m_state[1] += b;
				m_state[2] += c;
				m_state[3] += d;
				m_state[4] += e;
				m_state[5] += f;
				m_state[6] += g;
				m_state[7] += h;
			}

			std::array<std::uint32_t, 8> m_state = {
				0x6a09e667,
				0xbb67ae85,
				0x3c6ef372,
				0xa54ff53a,
				0x510e527f,
				0x9b05688c,
				0x1f83d9ab,
				0x5be0cd19,
			};
			std::array<std::uint8_t, 64> m_block{};
			std::size_t m_block_size = 0;
			std::uint64_t m_bit_count = 0;
		};

		class key_writer
		{
		public:
			void bytes(const std::span<const std::uint8_t> value)
			{
				m_hash.update(value);
			}

			void boolean(const bool value)
			{
				u8(value ? 1 : 0);
			}

			void u8(const std::uint8_t value)
			{
				m_hash.update(std::span(&value, 1));
			}

			void u32(const std::uint32_t value)
			{
				const std::array<std::uint8_t, 4> data = {
					static_cast<std::uint8_t>(value),
					static_cast<std::uint8_t>(value >> 8),
					static_cast<std::uint8_t>(value >> 16),
					static_cast<std::uint8_t>(value >> 24),
				};
				bytes(data);
			}

			void u64(const std::uint64_t value)
			{
				for (std::uint32_t shift = 0; shift < 64; shift += 8)
				{
					u8(static_cast<std::uint8_t>(value >> shift));
				}
			}

			void string(const std::string_view value)
			{
				u64(value.size());
				bytes(std::span(reinterpret_cast<const std::uint8_t*>(value.data()), value.size()));
			}

			stable_digest finish()
			{
				return m_hash.finish();
			}

		private:
			sha256 m_hash;
		};

		auto resource_sort_key(const resource_binding& value)
		{
			return std::tie(value.stage, value.descriptor_set, value.binding, value.kind, value.msl_buffer, value.msl_texture, value.msl_sampler, value.name);
		}

		void write_resource(key_writer& writer, const resource_binding& value)
		{
			writer.u8(static_cast<std::uint8_t>(value.stage));
			writer.u8(static_cast<std::uint8_t>(value.kind));
			writer.u8(static_cast<std::uint8_t>(value.access));
			writer.u32(value.descriptor_set);
			writer.u32(value.binding);
			writer.u32(value.array_count);
			writer.u32(value.msl_buffer);
			writer.u32(value.msl_texture);
			writer.u32(value.msl_sampler);
			writer.boolean(value.dynamic_offset);
			writer.u32(value.dynamic_offset_index);
			writer.boolean(value.inline_uniform_block);
			writer.boolean(value.discrete_descriptor_set);
			writer.boolean(value.argument_buffer_device_storage);
			writer.string(value.name);
		}

		void write_interface(key_writer& writer, const interface_variable& value)
		{
			writer.u32(value.location);
			writer.u32(value.component);
			writer.u8(static_cast<std::uint8_t>(value.format));
			writer.u32(value.builtin);
			writer.u32(value.vector_size);
			writer.u8(static_cast<std::uint8_t>(value.rate));
		}

		bool uses_buffer(const resource_kind kind)
		{
			return kind == resource_kind::uniform_buffer || kind == resource_kind::storage_buffer || kind == resource_kind::push_constant;
		}

		bool uses_texture(const resource_kind kind)
		{
			return kind == resource_kind::texel_buffer || kind == resource_kind::sampled_texture ||
			       kind == resource_kind::storage_texture || kind == resource_kind::combined_image_sampler ||
			       kind == resource_kind::input_attachment;
		}

		bool uses_sampler(const resource_kind kind)
		{
			return kind == resource_kind::sampler || kind == resource_kind::combined_image_sampler;
		}

		std::size_t expected_constant_size(const function_constant_type type)
		{
			switch (type)
			{
			case function_constant_type::boolean:
			case function_constant_type::int8:
			case function_constant_type::uint8:
				return 1;
			case function_constant_type::int16:
			case function_constant_type::uint16:
			case function_constant_type::float16:
				return 2;
			case function_constant_type::int32:
			case function_constant_type::uint32:
			case function_constant_type::float32:
				return 4;
			}
			return 0;
		}

		std::string validate_resources(const shader_metadata& metadata)
		{
			std::set<std::pair<std::uint32_t, std::uint32_t>> spirv_bindings;
			std::set<std::uint32_t> buffer_slots;
			std::set<std::uint32_t> texture_slots;
			std::set<std::uint32_t> sampler_slots;
			bool push_constant_seen = false;
			const std::set<std::uint32_t> reserved_buffer_slots = {
				metadata.policy.swizzle_buffer_index,
				metadata.policy.indirect_params_buffer_index,
				metadata.policy.shader_output_buffer_index,
				metadata.policy.buffer_size_buffer_index,
				metadata.policy.dynamic_offsets_buffer_index,
			};

			for (const resource_binding& resource : metadata.resources)
			{
				if (resource.stage != metadata.stage)
				{
					return "Resource stage does not match shader stage";
				}
				if (resource.array_count == 0 || resource.array_count > max_metal_binding_index + 1)
				{
					return "MSL resource arrays require a bounded nonzero size";
				}
				if (resource.kind != resource_kind::push_constant &&
					!spirv_bindings.emplace(resource.descriptor_set, resource.binding).second)
				{
					return "Duplicate SPIR-V descriptor set/binding metadata";
				}
				if (resource.kind == resource_kind::push_constant && std::exchange(push_constant_seen, true))
				{
					return "Duplicate push-constant binding metadata";
				}
				if (uses_buffer(resource.kind))
				{
					if (resource.msl_buffer == invalid_binding || resource.msl_buffer > max_metal_binding_index)
					{
						return "Buffer resource has an invalid Metal buffer index";
					}
					for (std::uint32_t index = 0; index < resource.array_count; ++index)
					{
						const std::uint32_t slot = resource.msl_buffer + index;
						if (slot > max_metal_binding_index || reserved_buffer_slots.contains(slot) || !buffer_slots.insert(slot).second)
						{
							return "Metal buffer binding collides with another or an auxiliary binding";
						}
					}
				}
				if (uses_texture(resource.kind))
				{
					if (resource.msl_texture == invalid_binding || resource.msl_texture > max_metal_binding_index)
					{
						return "Texture resource has an invalid Metal texture index";
					}
					for (std::uint32_t index = 0; index < resource.array_count; ++index)
					{
						if (resource.msl_texture + index > max_metal_binding_index || !texture_slots.insert(resource.msl_texture + index).second)
						{
							return "Metal texture binding collision";
						}
					}
				}
				if (uses_sampler(resource.kind))
				{
					if (resource.msl_sampler == invalid_binding || resource.msl_sampler > max_metal_binding_index)
					{
						return "Sampler resource has an invalid Metal sampler index";
					}
					for (std::uint32_t index = 0; index < resource.array_count; ++index)
					{
						if (resource.msl_sampler + index > max_metal_binding_index || !sampler_slots.insert(resource.msl_sampler + index).second)
						{
							return "Metal sampler binding collision";
						}
					}
				}
				if (resource.dynamic_offset && !metadata.policy.argument_buffers)
				{
					return "Dynamic offsets require the argument-buffer policy";
				}
				if ((resource.inline_uniform_block || resource.argument_buffer_device_storage) && !metadata.policy.argument_buffers)
				{
					return "Argument-buffer resource metadata requires the argument-buffer policy";
				}
			}
			return {};
		}
	} // namespace

	std::string stable_digest::hex() const
	{
		static constexpr char digits[] = "0123456789abcdef";
		std::string result(bytes.size() * 2, '0');
		for (std::size_t index = 0; index < bytes.size(); ++index)
		{
			result[index * 2] = digits[bytes[index] >> 4];
			result[index * 2 + 1] = digits[bytes[index] & 0xf];
		}
		return result;
	}

	std::size_t stable_digest_hash::operator()(const stable_digest& digest) const noexcept
	{
		std::size_t result = 0;
		constexpr std::size_t count = std::min(sizeof(result), std::size_t{8});
		for (std::size_t index = 0; index < count; ++index)
		{
			result |= static_cast<std::size_t>(digest.bytes[index]) << (index * 8);
		}
		return result;
	}

	std::string validate_shader_source(const shader_source& source)
	{
		if (source.spirv.size() < 5 || source.spirv.front() != spirv_magic)
		{
			return "Shader input is not a SPIR-V word stream";
		}
		if (source.metadata.entry_point.empty())
		{
			return "SPIR-V entry point cannot be empty";
		}
		if (source.metadata.policy.spirv_cross_revision.empty())
		{
			return "Pinned SPIRV-Cross revision is required for stable shader keys";
		}
		if (source.metadata.policy.msl_major != 2 || source.metadata.policy.msl_minor != 4 || source.metadata.policy.msl_patch != 0)
		{
			return "This iOS 15 slice accepts MSL 2.4 only";
		}
		if (source.metadata.policy.precision != precision_policy::preserve_spirv || !source.metadata.policy.preserve_invariance)
		{
			return "RSX precision and invariance preservation cannot be disabled";
		}
		if (source.metadata.policy.argument_buffer_tier < 1 || source.metadata.policy.argument_buffer_tier > 2)
		{
			return "Metal argument-buffer tier must be 1 or 2";
		}
		if (const std::string error = validate_resources(source.metadata); !error.empty())
		{
			return error;
		}

		std::set<std::uint32_t> input_locations;
		for (const interface_variable& input : source.metadata.inputs)
		{
			if (input.builtin == invalid_binding && !input_locations.insert(input.location).second)
			{
				return "Duplicate shader input location";
			}
		}
		std::set<std::uint32_t> output_locations;
		for (const interface_variable& output : source.metadata.outputs)
		{
			if (output.builtin == invalid_binding && !output_locations.insert(output.location).second)
			{
				return "Duplicate shader output location";
			}
		}
		std::set<std::uint32_t> fragment_locations;
		for (const fragment_output_components& output : source.metadata.fragment_outputs)
		{
			if (source.metadata.stage != shader_stage::fragment || output.components == 0 || output.components > 4 ||
				!fragment_locations.insert(output.location).second)
			{
				return "Invalid fragment output component metadata";
			}
		}
		std::set<std::uint32_t> constant_indices;
		for (const function_constant& constant : source.metadata.function_constants)
		{
			if (constant.value_size != expected_constant_size(constant.type) || !constant_indices.insert(constant.index).second)
			{
				return "Invalid or duplicate Metal function constant";
			}
		}
		return {};
	}

	std::string validate_render_pipeline_source(const render_pipeline_source& source)
	{
		if (source.vertex.metadata.stage != shader_stage::vertex || source.fragment.metadata.stage != shader_stage::fragment)
		{
			return "Render pipeline requires vertex and fragment shader stages";
		}
		if (const std::string error = validate_shader_source(source.vertex); !error.empty())
		{
			return "Vertex shader: " + error;
		}
		if (const std::string error = validate_shader_source(source.fragment); !error.empty())
		{
			return "Fragment shader: " + error;
		}
		if (source.pipeline.color_attachments.size() > max_color_attachments || source.pipeline.sample_count == 0 ||
			source.pipeline.max_vertex_amplification_count == 0)
		{
			return "Invalid Metal render pipeline attachment or sample metadata";
		}
		std::set<std::uint32_t> attribute_indices;
		for (const vertex_attribute_state& attribute : source.pipeline.vertex_attributes)
		{
			if (attribute.attribute_index > max_metal_binding_index || attribute.buffer_index > max_metal_binding_index ||
				attribute.format == 0 || !attribute_indices.insert(attribute.attribute_index).second)
			{
				return "Invalid or duplicate Metal vertex attribute metadata";
			}
		}
		std::set<std::uint32_t> layout_indices;
		for (const vertex_buffer_layout_state& layout : source.pipeline.vertex_layouts)
		{
			if (layout.buffer_index > max_metal_binding_index || !layout_indices.insert(layout.buffer_index).second)
			{
				return "Invalid or duplicate Metal vertex buffer layout metadata";
			}
		}
		return {};
	}

	stable_digest make_shader_cache_key(const shader_source& source)
	{
		key_writer writer;
		writer.string("ARMSX3-RSX-MTL-SHADER");
		writer.u32(shader_key_schema_version);
		writer.u8(static_cast<std::uint8_t>(source.metadata.stage));
		writer.string(source.metadata.entry_point);

		const translation_policy& policy = source.metadata.policy;
		writer.string(policy.spirv_cross_revision);
		writer.u32(policy.msl_major);
		writer.u32(policy.msl_minor);
		writer.u32(policy.msl_patch);
		writer.u8(static_cast<std::uint8_t>(policy.precision));
		writer.boolean(policy.preserve_invariance);
		writer.boolean(policy.invariant_float_math);
		writer.boolean(policy.ios_support_base_vertex_instance);
		writer.boolean(policy.enable_base_index_zero);
		writer.boolean(policy.pad_fragment_output_components);
		writer.boolean(policy.texture_buffer_native);
		writer.boolean(policy.argument_buffers);
		writer.u8(policy.argument_buffer_tier);
		writer.boolean(policy.force_active_argument_buffer_resources);
		writer.boolean(policy.pad_argument_buffer_resources);
		writer.boolean(policy.swizzle_texture_samples);
		writer.boolean(policy.manual_helper_invocation_updates);
		writer.boolean(policy.readwrite_texture_fences);
		writer.boolean(policy.agx_manual_cube_grad_fixup);
		writer.boolean(policy.force_fragment_with_side_effects_execution);
		writer.boolean(policy.auto_disable_rasterization);
		writer.u32(policy.enabled_fragment_output_mask);
		writer.u32(policy.fixed_sample_mask);
		writer.u32(policy.texel_buffer_texture_width);
		writer.u32(policy.swizzle_buffer_index);
		writer.u32(policy.indirect_params_buffer_index);
		writer.u32(policy.shader_output_buffer_index);
		writer.u32(policy.buffer_size_buffer_index);
		writer.u32(policy.dynamic_offsets_buffer_index);

		std::vector<resource_binding> resources = source.metadata.resources;
		std::sort(resources.begin(), resources.end(), [](const auto& left, const auto& right)
			{
				return resource_sort_key(left) < resource_sort_key(right);
			});
		writer.u64(resources.size());
		for (const resource_binding& resource : resources)
		{
			write_resource(writer, resource);
		}

		auto interfaces = [&writer](std::vector<interface_variable> values)
		{
			std::sort(values.begin(), values.end(), [](const auto& left, const auto& right)
				{
					return std::tie(left.builtin, left.location, left.component, left.format, left.vector_size, left.rate) <
				           std::tie(right.builtin, right.location, right.component, right.format, right.vector_size, right.rate);
				});
			writer.u64(values.size());
			for (const interface_variable& value : values)
			{
				write_interface(writer, value);
			}
		};
		interfaces(source.metadata.inputs);
		interfaces(source.metadata.outputs);

		std::vector<fragment_output_components> fragment_outputs = source.metadata.fragment_outputs;
		std::sort(fragment_outputs.begin(), fragment_outputs.end(), [](const auto& left, const auto& right)
			{
				return left.location < right.location;
			});
		writer.u64(fragment_outputs.size());
		for (const auto& output : fragment_outputs)
		{
			writer.u32(output.location);
			writer.u32(output.components);
		}

		std::vector<function_constant> constants = source.metadata.function_constants;
		std::sort(constants.begin(), constants.end(), [](const auto& left, const auto& right)
			{
				return left.index < right.index;
			});
		writer.u64(constants.size());
		for (const function_constant& constant : constants)
		{
			writer.u32(constant.index);
			writer.u8(static_cast<std::uint8_t>(constant.type));
			writer.u8(constant.value_size);
			writer.bytes(std::span(constant.value.data(), constant.value_size));
		}

		writer.u64(source.spirv.size());
		for (const std::uint32_t word : source.spirv)
		{
			writer.u32(word);
		}
		return writer.finish();
	}

	stable_digest make_render_pipeline_cache_key(
		const stable_digest& vertex_key,
		const stable_digest& fragment_key,
		const render_pipeline_metadata& metadata)
	{
		key_writer writer;
		writer.string("ARMSX3-RSX-MTL-RENDER-PIPELINE");
		writer.u32(pipeline_key_schema_version);
		writer.bytes(vertex_key.bytes);
		writer.bytes(fragment_key.bytes);
		writer.u64(metadata.color_attachments.size());
		for (const color_attachment_state& attachment : metadata.color_attachments)
		{
			writer.u64(attachment.pixel_format);
			writer.boolean(attachment.blending_enabled);
			writer.u64(attachment.source_rgb_blend_factor);
			writer.u64(attachment.destination_rgb_blend_factor);
			writer.u64(attachment.rgb_blend_operation);
			writer.u64(attachment.source_alpha_blend_factor);
			writer.u64(attachment.destination_alpha_blend_factor);
			writer.u64(attachment.alpha_blend_operation);
			writer.u64(attachment.write_mask);
		}
		writer.u64(metadata.depth_attachment_pixel_format);
		writer.u64(metadata.stencil_attachment_pixel_format);
		writer.u32(metadata.sample_count);
		writer.u64(metadata.input_primitive_topology);
		writer.boolean(metadata.alpha_to_coverage_enabled);
		writer.boolean(metadata.alpha_to_one_enabled);
		writer.boolean(metadata.rasterization_enabled);
		writer.boolean(metadata.support_indirect_command_buffers);
		writer.u32(metadata.max_vertex_amplification_count);

		std::vector<vertex_attribute_state> attributes = metadata.vertex_attributes;
		std::sort(attributes.begin(), attributes.end(), [](const auto& left, const auto& right)
			{
				return left.attribute_index < right.attribute_index;
			});
		writer.u64(attributes.size());
		for (const vertex_attribute_state& attribute : attributes)
		{
			writer.u32(attribute.attribute_index);
			writer.u64(attribute.format);
			writer.u32(attribute.offset);
			writer.u32(attribute.buffer_index);
		}

		std::vector<vertex_buffer_layout_state> layouts = metadata.vertex_layouts;
		std::sort(layouts.begin(), layouts.end(), [](const auto& left, const auto& right)
			{
				return left.buffer_index < right.buffer_index;
			});
		writer.u64(layouts.size());
		for (const vertex_buffer_layout_state& layout : layouts)
		{
			writer.u32(layout.buffer_index);
			writer.u32(layout.stride);
			writer.u64(layout.step_function);
			writer.u32(layout.step_rate);
		}
		return writer.finish();
	}
} // namespace rsx::mtl
