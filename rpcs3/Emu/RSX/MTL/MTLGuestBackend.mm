#include "MTLGuestBackend.h"
#include "MTLNativeShaderCache.h"
#include "MTLRSXShaderProgram.h"
#include "MTLUploadArena.h"

#include "Emu/RSX/Common/TextureUtils.h"
#include "Emu/RSX/Common/surface_store.h"
#include "Emu/RSX/Program/ProgramStateCache.h"
#include "Emu/RSX/Program/SPIRVCommon.h"
#include "Emu/RSX/rsx_methods.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <unordered_map>
#include <utility>

namespace
{
	using metal_device_ref = id<MTLDevice>;
	using metal_buffer_ref = id<MTLBuffer>;
	using metal_command_buffer_ref = id<MTLCommandBuffer>;
	using metal_render_encoder_ref = id<MTLRenderCommandEncoder>;
	using metal_texture_ref = id<MTLTexture>;

	constexpr u64 target_retirement_age = 180;
	constexpr usz target_cache_limit = 96;
	constexpr usz rsx_program_cache_limit = 512;
	constexpr usz draw_parameters_bytes = 168;
	constexpr usz vertex_context_bytes = 96;
	constexpr usz fragment_context_bytes = 32;
	constexpr usz texture_parameters_bytes = 768;
	constexpr usz rasterizer_heap_bytes = 128;

	struct draw_parameters
	{
		u32 vertex_base_index = 0;
		u32 vertex_index_offset = 0;
		u32 draw_id = 0;
		u32 xform_constants_offset = 0;
		u32 vs_context_offset = 0;
		u32 fs_constants_offset = 0;
		u32 fs_context_offset = 0;
		u32 fs_texture_base_index = 0;
		u32 fs_stipple_pattern_offset = 0;
		u32 reserved = 0;
		s32 attrib_data[32]{};
	};

	static_assert(sizeof(draw_parameters) == draw_parameters_bytes);

	struct draw_uploads
	{
		mtl::upload_allocation persistent_vertices{};
		mtl::upload_allocation volatile_vertices{};
		mtl::upload_allocation parameters{};
		mtl::upload_allocation vertex_context{};
		mtl::upload_allocation vertex_constants{};
		mtl::upload_allocation fragment_constants{};
		mtl::upload_allocation fragment_context{};
		mtl::upload_allocation texture_parameters{};
		mtl::upload_allocation rasterizer_heap{};
		__strong metal_texture_ref persistent_vertex_view = nil;
		__strong metal_texture_ref volatile_vertex_view = nil;
	};

	struct native_primitive
	{
		MTLPrimitiveType type = MTLPrimitiveTypeTriangle;
		MTLPrimitiveTopologyClass topology = MTLPrimitiveTopologyClassTriangle;
	};

	using vertex_spirv_cache = std::unordered_map<
		RSXVertexProgram,
		rsx::mtl::rsx_shader_program,
		program_hash_util::vertex_program_storage_hash,
		program_hash_util::vertex_program_compare>;
	using fragment_spirv_cache = std::unordered_map<
		RSXFragmentProgram,
		rsx::mtl::rsx_shader_program,
		program_hash_util::fragment_program_storage_hash,
		program_hash_util::fragment_program_compare>;

	std::optional<native_primitive> native_primitive_for(rsx::primitive_type primitive)
	{
		switch (primitive)
		{
		case rsx::primitive_type::points:
			return native_primitive{MTLPrimitiveTypePoint, MTLPrimitiveTopologyClassPoint};
		case rsx::primitive_type::lines:
			return native_primitive{MTLPrimitiveTypeLine, MTLPrimitiveTopologyClassLine};
		case rsx::primitive_type::line_strip:
			return native_primitive{MTLPrimitiveTypeLineStrip, MTLPrimitiveTopologyClassLine};
		case rsx::primitive_type::triangles:
			return native_primitive{MTLPrimitiveTypeTriangle, MTLPrimitiveTopologyClassTriangle};
		case rsx::primitive_type::triangle_strip:
			return native_primitive{MTLPrimitiveTypeTriangleStrip, MTLPrimitiveTopologyClassTriangle};
		default:
			return std::nullopt;
		}
	}

	std::string objc_string(NSString* value, std::string_view fallback)
	{
		if (const char* text = value.UTF8String)
		{
			return text;
		}

		return std::string(fallback);
	}

	std::string metal_error(NSError* error, std::string_view fallback)
	{
		if (!error)
		{
			return std::string(fallback);
		}

		NSString* message = error.localizedDescription;
		if (error.localizedFailureReason.length)
		{
			message = [message stringByAppendingFormat:@" (%@)", error.localizedFailureReason];
		}
		return objc_string(message, fallback);
	}

	MTLPixelFormat color_pixel_format(rsx::surface_color_format format)
	{
		switch (format)
		{
		case rsx::surface_color_format::a8r8g8b8:
		case rsx::surface_color_format::x8r8g8b8_z8r8g8b8:
		case rsx::surface_color_format::x8r8g8b8_o8r8g8b8:
			return MTLPixelFormatBGRA8Unorm;
		case rsx::surface_color_format::a8b8g8r8:
		case rsx::surface_color_format::x8b8g8r8_z8b8g8r8:
		case rsx::surface_color_format::x8b8g8r8_o8b8g8r8:
			return MTLPixelFormatRGBA8Unorm;
		case rsx::surface_color_format::r5g6b5:
		case rsx::surface_color_format::x1r5g5b5_z1r5g5b5:
		case rsx::surface_color_format::x1r5g5b5_o1r5g5b5:
			// Apple render-target support for packed 16-bit formats varies by GPU.
			// Preserve logical channels in a renderable format; the final format
			// conversion module will quantize memory exports to the RSX layout.
			return MTLPixelFormatBGRA8Unorm;
		case rsx::surface_color_format::b8:
			return MTLPixelFormatR8Unorm;
		case rsx::surface_color_format::g8b8:
			return MTLPixelFormatRG8Unorm;
		case rsx::surface_color_format::w16z16y16x16:
			return MTLPixelFormatRGBA16Float;
		case rsx::surface_color_format::w32z32y32x32:
			return MTLPixelFormatRGBA32Float;
		case rsx::surface_color_format::x32:
			return MTLPixelFormatR32Float;
		}

		return MTLPixelFormatInvalid;
	}

	MTLPixelFormat depth_pixel_format(rsx::surface_depth_format2 format)
	{
		switch (format)
		{
		case rsx::surface_depth_format2::z16_uint:
			return MTLPixelFormatDepth16Unorm;
		case rsx::surface_depth_format2::z16_float:
			return MTLPixelFormatDepth32Float;
		case rsx::surface_depth_format2::z24s8_uint:
		case rsx::surface_depth_format2::z24s8_float:
			return MTLPixelFormatDepth32Float_Stencil8;
		}

		return MTLPixelFormatInvalid;
	}

	bool has_stencil(MTLPixelFormat format)
	{
		return format == MTLPixelFormatDepth32Float_Stencil8 ||
		       format == MTLPixelFormatX32_Stencil8;
	}

	struct color_target
	{
		u32 address = 0;
		u32 pitch = 0;
		u32 width = 0;
		u32 height = 0;
		u32 samples = 1;
		rsx::surface_color_format format{};
		MTLPixelFormat pixel_format = MTLPixelFormatInvalid;
		__strong metal_texture_ref texture = nil;
		__strong metal_texture_ref resolve_texture = nil;
		u64 last_used_frame = 0;

		bool matches(
			u32 requested_pitch,
			u32 requested_width,
			u32 requested_height,
			u32 requested_samples,
			rsx::surface_color_format requested_format,
			MTLPixelFormat requested_pixel_format) const
		{
			return pitch == requested_pitch && width == requested_width && height == requested_height &&
			       samples == requested_samples && format == requested_format &&
			       pixel_format == requested_pixel_format;
		}
	};

	struct depth_target
	{
		u32 address = 0;
		u32 pitch = 0;
		u32 width = 0;
		u32 height = 0;
		u32 samples = 1;
		rsx::surface_depth_format2 format{};
		MTLPixelFormat pixel_format = MTLPixelFormatInvalid;
		__strong metal_texture_ref texture = nil;
		u64 last_used_frame = 0;

		bool matches(
			u32 requested_pitch,
			u32 requested_width,
			u32 requested_height,
			u32 requested_samples,
			rsx::surface_depth_format2 requested_format,
			MTLPixelFormat requested_pixel_format) const
		{
			return pitch == requested_pitch && width == requested_width && height == requested_height &&
			       samples == requested_samples && format == requested_format &&
			       pixel_format == requested_pixel_format;
		}
	};

	struct present_pipeline
	{
		__strong id<MTLRenderPipelineState> state = nil;
	};

	const char* present_shader_source = R"MSL(
#include <metal_stdlib>
using namespace metal;

struct ARMSX3PresentVertex
{
	float4 position [[position]];
	float2 uv;
};

vertex ARMSX3PresentVertex armsx3_present_vertex(uint vertex_id [[vertex_id]])
{
	constexpr float2 positions[] = {
		float2(-1.0, -1.0),
		float2( 3.0, -1.0),
		float2(-1.0,  3.0),
	};
	constexpr float2 texcoords[] = {
		float2(0.0, 1.0),
		float2(2.0, 1.0),
		float2(0.0, -1.0),
	};

	ARMSX3PresentVertex output;
	output.position = float4(positions[vertex_id], 0.0, 1.0);
	output.uv = texcoords[vertex_id];
	return output;
}

fragment float4 armsx3_present_fragment(
	ARMSX3PresentVertex input [[stage_in]],
	texture2d<float> source [[texture(0)]],
	sampler source_sampler [[sampler(0)]])
{
	return source.sample(source_sampler, input.uv);
}
)MSL";
} // namespace

namespace mtl
{
	class native_guest_backend final : public guest_backend
	{
	public:
		bool initialize(const device_context& context, std::string& error) override
		{
			@autoreleasepool
			{
				@try
				{
					if (!context.device)
					{
						error = "Metal device is null";
						return false;
					}

					id candidate = (__bridge id)context.device;
					if (![candidate conformsToProtocol:@protocol(MTLDevice)])
					{
						error = "Native object does not conform to MTLDevice";
						return false;
					}

					m_device = candidate;
					if (context.registry_id && context.registry_id != m_device.registryID)
					{
						error = "Metal device registry ID changed across the renderer boundary";
						return false;
					}

					m_uploads = std::make_unique<upload_arena>((__bridge void*)m_device);
					if (!m_uploads->valid())
					{
						error = m_uploads->initialization_error();
						return false;
					}

					m_shader_cache = std::make_unique<rsx::mtl::native_shader_cache>((__bridge void*)m_device);
					if (!m_shader_cache->valid())
					{
						error = m_shader_cache->initialization_error();
						return false;
					}

					NSString* source = [NSString stringWithUTF8String:present_shader_source];
					MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
					options.languageVersion = MTLLanguageVersion2_4;
					options.fastMathEnabled = NO;
					options.preserveInvariance = YES;

					NSError* library_error = nil;
					m_present_library = [m_device newLibraryWithSource:source options:options error:&library_error];
					if (!m_present_library)
					{
						error = metal_error(library_error, "Metal failed to compile the guest presentation shader");
						return false;
					}
					m_present_library.label = @"ARMSX3 native Metal guest presenter";
					m_present_vertex = [m_present_library newFunctionWithName:@"armsx3_present_vertex"];
					m_present_fragment = [m_present_library newFunctionWithName:@"armsx3_present_fragment"];
					if (!m_present_vertex || !m_present_fragment)
					{
						error = "Guest presentation MSL did not expose both entry points";
						return false;
					}

					MTLSamplerDescriptor* sampler_descriptor = [[MTLSamplerDescriptor alloc] init];
					sampler_descriptor.minFilter = MTLSamplerMinMagFilterLinear;
					sampler_descriptor.magFilter = MTLSamplerMinMagFilterLinear;
					sampler_descriptor.mipFilter = MTLSamplerMipFilterNotMipmapped;
					sampler_descriptor.sAddressMode = MTLSamplerAddressModeClampToEdge;
					sampler_descriptor.tAddressMode = MTLSamplerAddressModeClampToEdge;
					m_present_sampler = [m_device newSamplerStateWithDescriptor:sampler_descriptor];
					if (!m_present_sampler)
					{
						error = "Metal failed to create the guest presentation sampler";
						return false;
					}

					spirv::initialize_compiler_context();
					m_compiler_initialized = true;
				}
				@catch (NSException* exception)
				{
					error = objc_string(exception.reason, "Objective-C exception during native guest initialization");
					return false;
				}
			}

			return true;
		}

		bool begin_frame(const command_context& context, std::string& error) override
		{
			if (m_frame_open)
			{
				error = "A native Metal guest frame is already open";
				return false;
			}
			if (!validate_context(context, error))
			{
				return false;
			}
			if (!m_uploads || !m_uploads->begin_frame(context.frame_index, error))
			{
				if (error.empty())
				{
					error = "Metal upload arena is unavailable";
				}
				return false;
			}

			m_frame_index = context.frame_index;
			m_frame_open = true;
			m_active_colors.fill(nullptr);
			m_active_depth = nullptr;
			return true;
		}

		bool prepare_framebuffer(
			const command_context& context,
			rsx::framebuffer_creation_context,
			const rsx::framebuffer_layout& layout,
			std::string& error) override
		{
			if (!validate_open_frame(context, error))
			{
				return false;
			}
			if (!layout.width || !layout.height)
			{
				error = "RSX framebuffer has zero width or height";
				return false;
			}

			const u32 samples = get_format_sample_count(layout.aa_mode);
			if (![m_device supportsTextureSampleCount:samples])
			{
				error = "Apple GPU does not support the requested RSX sample count " + std::to_string(samples);
				return false;
			}

			m_active_colors.fill(nullptr);
			for (const u8 index : rsx::utility::get_rtt_indexes(layout.target))
			{
				if (!layout.color_addresses[index] || !layout.actual_color_pitch[index])
				{
					error = "Active RSX color target has no address or pitch";
					return false;
				}

				color_target* target = prepare_color_target(
					layout.color_addresses[index],
					layout.actual_color_pitch[index],
					layout.width,
					layout.height,
					samples,
					layout.color_format,
					error);
				if (!target)
				{
					return false;
				}
				m_active_colors[index] = target;
			}

			m_active_depth = nullptr;
			if (layout.zeta_address)
			{
				if (!layout.actual_zeta_pitch)
				{
					error = "Active RSX depth target has no pitch";
					return false;
				}

				m_active_depth = prepare_depth_target(
					layout.zeta_address,
					layout.actual_zeta_pitch,
					layout.width,
					layout.height,
					samples,
					layout.depth_format,
					error);
				if (!m_active_depth)
				{
					return false;
				}
			}

			m_framebuffer_width = layout.width;
			m_framebuffer_height = layout.height;
			m_framebuffer_samples = samples;
			return true;
		}

		bool encode_clear(
			const command_context& context,
			const clear_request& request,
			std::string& error) override
		{
			if (!validate_open_frame(context, error))
			{
				return false;
			}
			if (!request.framebuffer)
			{
				error = "Clear request has no framebuffer layout";
				return false;
			}

			const u32 color_mask = request.mask & RSX_GCM_CLEAR_COLOR_RGBA_MASK;
			if (color_mask && color_mask != RSX_GCM_CLEAR_COLOR_RGBA_MASK)
			{
				error = "Partial-channel RSX clears require the native clear pipeline";
				return false;
			}
			if ((request.scissor.x || request.scissor.y ||
					request.scissor.width < m_framebuffer_width || request.scissor.height < m_framebuffer_height) &&
				request.mask)
			{
				error = "Scissored RSX clears require the native clear pipeline";
				return false;
			}

			@autoreleasepool
			{
				@try
				{
					MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
					bool has_attachment = false;
					for (usz index = 0; index < m_active_colors.size(); ++index)
					{
						color_target* target = m_active_colors[index];
						if (!target)
						{
							continue;
						}

						MTLRenderPassColorAttachmentDescriptor* attachment = pass.colorAttachments[index];
						attachment.texture = target->texture;
						attachment.loadAction = color_mask ? MTLLoadActionClear : MTLLoadActionLoad;
						attachment.clearColor = MTLClearColorMake(
							request.color[0], request.color[1], request.color[2], request.color[3]);
						if (target->resolve_texture)
						{
							attachment.resolveTexture = target->resolve_texture;
							attachment.storeAction = MTLStoreActionStoreAndMultisampleResolve;
						}
						else
						{
							attachment.storeAction = MTLStoreActionStore;
						}
						has_attachment = true;
					}

					if (m_active_depth)
					{
						pass.depthAttachment.texture = m_active_depth->texture;
						pass.depthAttachment.loadAction = (request.mask & RSX_GCM_CLEAR_DEPTH_BIT) ? MTLLoadActionClear : MTLLoadActionLoad;
						pass.depthAttachment.storeAction = MTLStoreActionStore;
						pass.depthAttachment.clearDepth = request.depth;

						if (has_stencil(m_active_depth->pixel_format))
						{
							pass.stencilAttachment.texture = m_active_depth->texture;
							pass.stencilAttachment.loadAction = (request.mask & RSX_GCM_CLEAR_STENCIL_BIT) ? MTLLoadActionClear : MTLLoadActionLoad;
							pass.stencilAttachment.storeAction = MTLStoreActionStore;
							pass.stencilAttachment.clearStencil = request.stencil;
						}
						has_attachment = true;
					}

					if (!has_attachment)
					{
						return true;
					}

					metal_command_buffer_ref command_buffer = (__bridge metal_command_buffer_ref)context.command_buffer;
					id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
					if (!encoder)
					{
						error = "Metal returned no encoder for the RSX clear pass";
						return false;
					}
					encoder.label = @"ARMSX3 native RSX clear";
					[encoder endEncoding];
				}
				@catch (NSException* exception)
				{
					error = objc_string(exception.reason, "Objective-C exception while encoding an RSX clear");
					return false;
				}
			}

			return true;
		}

		bool encode_draw(
			const command_context& context,
			const draw_request& request,
			std::string& error) override
		{
			if (!validate_open_frame(context, error))
			{
				return false;
			}
			if (!request.renderer || !request.vertex_program || !request.fragment_program ||
				!request.framebuffer || !request.vertex_layout)
			{
				error = "RSX draw request is missing renderer, program, framebuffer, or vertex-layout state";
				return false;
			}
			if (!request.count || !request.scissor.width || !request.scissor.height)
			{
				return true;
			}
			if (request.command != rsx::draw_command::array || request.indexed || request.inline_vertices)
			{
				error = "The first native Metal draw path accepts non-indexed RSX array draws only";
				return false;
			}
			if (request.instance_count != 1)
			{
				error = "Native Metal RSX instancing is not implemented";
				return false;
			}

			const std::optional<native_primitive> primitive = native_primitive_for(request.primitive);
			if (!primitive)
			{
				error = "Native Metal primitive expansion is not implemented for RSX topology " +
				        std::to_string(static_cast<u32>(request.primitive));
				return false;
			}
			if (!validate_first_draw_state(request, error))
			{
				return false;
			}

			rsx::mtl::rsx_shader_capabilities shader_capabilities{};
			shader_capabilities.emulate_conditional_rendering = false;
			const auto* vertex_program = get_or_compile_vertex_program(
				*request.vertex_program, shader_capabilities, error);
			if (!vertex_program)
			{
				return false;
			}
			if (vertex_program->use_last_provoking_vertex)
			{
				error = "Native Metal last-vertex provoking semantics are not implemented";
				return false;
			}
			const auto* fragment_program = get_or_compile_fragment_program(
				*request.fragment_program, shader_capabilities, error);
			if (!fragment_program)
			{
				return false;
			}

			rsx::mtl::shader_source vertex_source = vertex_program->source();
			rsx::mtl::shader_source fragment_source = fragment_program->source();
			u32 active_output_mask = 0;
			usz attachment_count = 0;
			for (usz index = 0; index < m_active_colors.size(); ++index)
			{
				if (m_active_colors[index])
				{
					active_output_mask |= 1u << index;
					attachment_count = index + 1;
				}
			}
			if (!attachment_count && !m_active_depth)
			{
				error = "RSX draw has no active Metal render attachment";
				return false;
			}
			fragment_source.metadata.policy.enabled_fragment_output_mask = active_output_mask;

			auto vertex_shader = m_shader_cache->get_or_create_shader(vertex_source);
			if (!vertex_shader)
			{
				error = "Native Metal vertex translation failed: " + vertex_shader.error;
				return false;
			}
			auto fragment_shader = m_shader_cache->get_or_create_shader(fragment_source);
			if (!fragment_shader)
			{
				error = "Native Metal fragment translation failed: " + fragment_shader.error;
				return false;
			}
			if (!validate_translation(*vertex_shader.value.translation(), error) ||
				!validate_translation(*fragment_shader.value.translation(), error))
			{
				return false;
			}

			rsx::mtl::render_pipeline_metadata pipeline_metadata;
			pipeline_metadata.color_attachments.resize(attachment_count);
			for (usz index = 0; index < attachment_count; ++index)
			{
				auto& attachment = pipeline_metadata.color_attachments[index];
				if (const color_target* target = m_active_colors[index])
				{
					attachment.pixel_format = static_cast<u64>(target->pixel_format);
					attachment.write_mask = color_write_mask(static_cast<u32>(index));
				}
				else
				{
					attachment.write_mask = MTLColorWriteMaskNone;
				}
			}
			if (m_active_depth)
			{
				pipeline_metadata.depth_attachment_pixel_format = static_cast<u64>(m_active_depth->pixel_format);
				if (has_stencil(m_active_depth->pixel_format))
				{
					pipeline_metadata.stencil_attachment_pixel_format = static_cast<u64>(m_active_depth->pixel_format);
				}
			}
			pipeline_metadata.sample_count = m_framebuffer_samples;
			pipeline_metadata.input_primitive_topology = static_cast<u64>(primitive->topology);
			pipeline_metadata.alpha_to_coverage_enabled = rsx::method_registers.msaa_alpha_to_coverage_enabled();
			pipeline_metadata.alpha_to_one_enabled = rsx::method_registers.msaa_alpha_to_one_enabled();

			const rsx::mtl::render_pipeline_source pipeline_source
			{
				.vertex = vertex_source,
				.fragment = fragment_source,
				.pipeline = std::move(pipeline_metadata),
				.label = "ARMSX3 native RSX array draw",
			};
			auto pipeline = m_shader_cache->get_or_create_render_pipeline(pipeline_source);
			if (!pipeline)
			{
				error = "Native Metal render pipeline creation failed: " + pipeline.error;
				return false;
			}

			draw_uploads uploads;
			if (!prepare_draw_uploads(
					request,
					*vertex_program,
					*fragment_program,
					uploads,
					error))
			{
				return false;
			}

			@autoreleasepool
			{
				metal_render_encoder_ref encoder = nil;
				@try
				{
					MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
					bool has_attachment = false;
					for (usz index = 0; index < m_active_colors.size(); ++index)
					{
						color_target* target = m_active_colors[index];
						if (!target)
						{
							continue;
						}

						auto* attachment = pass.colorAttachments[index];
						attachment.texture = target->texture;
						attachment.loadAction = MTLLoadActionLoad;
						if (target->resolve_texture)
						{
							attachment.resolveTexture = target->resolve_texture;
							attachment.storeAction = MTLStoreActionStoreAndMultisampleResolve;
						}
						else
						{
							attachment.storeAction = MTLStoreActionStore;
						}
						has_attachment = true;
					}
					if (m_active_depth)
					{
						pass.depthAttachment.texture = m_active_depth->texture;
						pass.depthAttachment.loadAction = MTLLoadActionLoad;
						pass.depthAttachment.storeAction = MTLStoreActionStore;
						if (has_stencil(m_active_depth->pixel_format))
						{
							pass.stencilAttachment.texture = m_active_depth->texture;
							pass.stencilAttachment.loadAction = MTLLoadActionLoad;
							pass.stencilAttachment.storeAction = MTLStoreActionStore;
						}
						has_attachment = true;
					}
					if (!has_attachment)
					{
						error = "RSX draw has no active Metal render attachment";
						return false;
					}

					metal_command_buffer_ref command_buffer = (__bridge metal_command_buffer_ref)context.command_buffer;
					encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
					if (!encoder)
					{
						error = "Metal returned no encoder for the RSX array draw";
						return false;
					}
					encoder.label = @"ARMSX3 native RSX array draw";
					[encoder setViewport:MTLViewport{
						request.viewport_state.x,
						request.viewport_state.y,
						request.viewport_state.width,
						request.viewport_state.height,
						request.viewport_state.z_near,
						request.viewport_state.z_far,
					}];
					[encoder setScissorRect:MTLScissorRect{
						request.scissor.x,
						request.scissor.y,
						request.scissor.width,
						request.scissor.height,
					}];
					[encoder setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pipeline.value.native_pipeline_state()];
					bind_vertex_resources(encoder, *vertex_shader.value.translation(), uploads);
					bind_fragment_resources(encoder, *fragment_shader.value.translation(), uploads);
					[encoder drawPrimitives:primitive->type vertexStart:0 vertexCount:request.count];
					[encoder endEncoding];
				}
				@catch (NSException* exception)
				{
					if (encoder)
					{
						[encoder endEncoding];
					}
					error = objc_string(exception.reason, "Objective-C exception while encoding an RSX draw");
					return false;
				}
			}

			return true;
		}

		bool encode_present(
			const present_context& context,
			const present_request& request,
			std::string& error) override
		{
			if (!validate_open_frame(context.commands, error))
			{
				return false;
			}
			if (!request.valid_guest_buffer || !request.guest_address)
			{
				error = "RSX flip did not identify a valid guest display buffer";
				return false;
			}

			const auto target_iterator = m_color_targets.find(request.guest_address);
			if (target_iterator == m_color_targets.end())
			{
				error = "RSX display buffer has no native Metal render target";
				return false;
			}

			color_target& target = *target_iterator->second;
			metal_texture_ref source = target.resolve_texture ? target.resolve_texture : target.texture;
			if (!source)
			{
				error = "RSX display render target has no sampleable Metal texture";
				return false;
			}

			@autoreleasepool
			{
				@try
				{
					id drawable_candidate = (__bridge id)context.drawable_texture;
					if (![drawable_candidate conformsToProtocol:@protocol(MTLTexture)])
					{
						error = "Presentation object does not conform to MTLTexture";
						return false;
					}
					metal_texture_ref drawable = drawable_candidate;

					id<MTLRenderPipelineState> pipeline = present_pipeline_for(drawable.pixelFormat, error);
					if (!pipeline)
					{
						return false;
					}

					MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
					pass.colorAttachments[0].texture = drawable;
					pass.colorAttachments[0].loadAction = MTLLoadActionClear;
					pass.colorAttachments[0].storeAction = MTLStoreActionStore;
					pass.colorAttachments[0].clearColor = MTLClearColorMake(0., 0., 0., 1.);

					metal_command_buffer_ref command_buffer = (__bridge metal_command_buffer_ref)context.commands.command_buffer;
					id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
					if (!encoder)
					{
						error = "Metal returned no encoder for guest presentation";
						return false;
					}

					const double source_width = static_cast<double>(request.width ? request.width : target.width);
					const double source_height = static_cast<double>(request.height ? request.height : target.height);
					const double drawable_width = static_cast<double>(drawable.width);
					const double drawable_height = static_cast<double>(drawable.height);
					const double scale = std::min(drawable_width / source_width, drawable_height / source_height);
					const double viewport_width = std::max(1., std::floor(source_width * scale));
					const double viewport_height = std::max(1., std::floor(source_height * scale));
					const MTLViewport viewport =
						{
							(drawable_width - viewport_width) * .5,
							(drawable_height - viewport_height) * .5,
							viewport_width,
							viewport_height,
							0.,
							1.,
						};

					encoder.label = @"ARMSX3 native RSX presentation";
					[encoder setViewport:viewport];
					[encoder setRenderPipelineState:pipeline];
					[encoder setFragmentTexture:source atIndex:0];
					[encoder setFragmentSamplerState:m_present_sampler atIndex:0];
					[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
					[encoder endEncoding];
				}
				@catch (NSException* exception)
				{
					error = objc_string(exception.reason, "Objective-C exception during guest presentation");
					return false;
				}
			}

			return true;
		}

		bool finish_frame(
			const command_context& context,
			bool,
			std::string& error) override
		{
			if (!validate_open_frame(context, error))
			{
				return false;
			}
			if (!m_uploads || !m_uploads->finish_frame(
					context.frame_index, context.command_buffer, error))
			{
				if (error.empty())
				{
					error = "Metal upload arena could not finalize the frame";
				}
				return false;
			}

			m_active_colors.fill(nullptr);
			m_active_depth = nullptr;
			m_frame_open = false;
			trim_target_cache();
			return true;
		}

		void abandon_frame(u64 frame_index) noexcept override
		{
			if (m_uploads)
			{
				m_uploads->abandon_frame(frame_index);
			}
			if (m_frame_open && frame_index == m_frame_index)
			{
				m_active_colors.fill(nullptr);
				m_active_depth = nullptr;
				m_frame_open = false;
			}
		}

		void shutdown() noexcept override
		{
			if (m_uploads)
			{
				if (m_frame_open)
				{
					m_uploads->abandon_frame(m_frame_index);
				}
				m_uploads->shutdown();
				m_uploads.reset();
			}
			m_active_colors.fill(nullptr);
			m_active_depth = nullptr;
			m_color_targets.clear();
			m_depth_targets.clear();
			m_present_pipelines.clear();
			m_vertex_spirv.clear();
			m_fragment_spirv.clear();
			m_shader_cache.reset();
			if (m_compiler_initialized)
			{
				spirv::finalize_compiler_context();
				m_compiler_initialized = false;
			}
			m_present_sampler = nil;
			m_present_vertex = nil;
			m_present_fragment = nil;
			m_present_library = nil;
			m_device = nil;
			m_frame_open = false;
		}

	private:
		const rsx::mtl::rsx_shader_program* get_or_compile_vertex_program(
			const RSXVertexProgram& program,
			const rsx::mtl::rsx_shader_capabilities& capabilities,
			std::string& error)
		{
			if (const auto found = m_vertex_spirv.find(program); found != m_vertex_spirv.end())
			{
				return &found->second;
			}

			auto compiled = rsx::mtl::compile_vertex_program_to_spirv(program, capabilities);
			if (!compiled)
			{
				error = "RSX vertex shader compilation failed: " + compiled.error;
				return nullptr;
			}
			if (m_vertex_spirv.size() >= rsx_program_cache_limit)
			{
				m_vertex_spirv.erase(m_vertex_spirv.begin());
			}
			const auto inserted = m_vertex_spirv.emplace(program, std::move(*compiled.program)).first;
			return &inserted->second;
		}

		const rsx::mtl::rsx_shader_program* get_or_compile_fragment_program(
			const RSXFragmentProgram& program,
			const rsx::mtl::rsx_shader_capabilities& capabilities,
			std::string& error)
		{
			if (const auto found = m_fragment_spirv.find(program); found != m_fragment_spirv.end())
			{
				return &found->second;
			}

			auto compiled = rsx::mtl::compile_fragment_program_to_spirv(program, capabilities);
			if (!compiled)
			{
				error = "RSX fragment shader compilation failed: " + compiled.error;
				return nullptr;
			}
			if (m_fragment_spirv.size() >= rsx_program_cache_limit)
			{
				m_fragment_spirv.erase(m_fragment_spirv.begin());
			}
			const auto inserted = m_fragment_spirv.emplace(program, std::move(*compiled.program)).first;
			return &inserted->second;
		}

		bool validate_first_draw_state(const draw_request& request, std::string& error) const
		{
			if (!m_shader_cache || !m_uploads)
			{
				error = "Native Metal shader or upload state is unavailable";
				return false;
			}
			if (request.renderer->current_vp_metadata.referenced_textures_mask ||
				request.renderer->current_fp_metadata.referenced_textures_mask)
			{
				error = "Native Metal sampled guest textures are not implemented";
				return false;
			}
			if (request.vertex_program->ctrl & RSX_SHADER_CONTROL_INSTANCED_CONSTANTS)
			{
				error = "Native Metal instanced vertex constants are not implemented";
				return false;
			}
			if (rsx::method_registers.blend_enabled() ||
				rsx::method_registers.blend_enabled_surface_1() ||
				rsx::method_registers.blend_enabled_surface_2() ||
				rsx::method_registers.blend_enabled_surface_3())
			{
				error = "Native Metal RSX blending is not implemented";
				return false;
			}
			if (rsx::method_registers.depth_test_enabled() || rsx::method_registers.stencil_test_enabled())
			{
				error = "Native Metal RSX depth/stencil testing is not implemented";
				return false;
			}
			if (rsx::method_registers.cull_face_enabled())
			{
				error = "Native Metal RSX face culling is not implemented";
				return false;
			}
			if (rsx::method_registers.logic_op_enabled())
			{
				error = "Native Metal RSX logic operations are not implemented";
				return false;
			}
			if (rsx::method_registers.depth_bounds_test_enabled())
			{
				error = "Native Metal RSX depth-bounds testing is not implemented";
				return false;
			}
			if (rsx::method_registers.poly_offset_point_enabled() ||
				rsx::method_registers.poly_offset_line_enabled() ||
				rsx::method_registers.poly_offset_fill_enabled())
			{
				error = "Native Metal RSX polygon offset is not implemented";
				return false;
			}
			if (rsx::method_registers.line_smooth_enabled() || rsx::method_registers.poly_smooth_enabled())
			{
				error = "Native Metal RSX line/polygon smoothing is not implemented";
				return false;
			}
			if (rsx::method_registers.polygon_stipple_enabled())
			{
				error = "Native Metal RSX polygon stipple is not implemented";
				return false;
			}
			return true;
		}

		u64 color_write_mask(u32 index) const
		{
			u64 result = MTLColorWriteMaskNone;
			if (rsx::method_registers.color_mask_r(index)) result |= MTLColorWriteMaskRed;
			if (rsx::method_registers.color_mask_g(index)) result |= MTLColorWriteMaskGreen;
			if (rsx::method_registers.color_mask_b(index)) result |= MTLColorWriteMaskBlue;
			if (rsx::method_registers.color_mask_a(index)) result |= MTLColorWriteMaskAlpha;
			return result;
		}

		bool validate_translation(const rsx::mtl::translated_shader& shader, std::string& error) const
		{
			const auto& requirements = shader.requirements;
			if (requirements.needs_swizzle_buffer || requirements.needs_buffer_size_buffer ||
				requirements.needs_output_buffer || requirements.needs_patch_output_buffer ||
				requirements.needs_input_threadgroup_memory || requirements.needs_dynamic_offset_buffer)
			{
				error = "Translated Metal shader requires an auxiliary SPIRV-Cross resource that is not implemented";
				return false;
			}

			for (const auto& translated : shader.resources)
			{
				if (!translated.active)
				{
					continue;
				}

				const auto& resource = translated.binding;
				bool supported = false;
				if (shader.metadata.stage == rsx::mtl::shader_stage::vertex)
				{
					supported =
						(resource.name == "persistent_input_stream" && resource.kind == rsx::mtl::resource_kind::texel_buffer) ||
						(resource.name == "volatile_input_stream" && resource.kind == rsx::mtl::resource_kind::texel_buffer) ||
						(resource.name == "DrawParametersBuffer" && resource.kind == rsx::mtl::resource_kind::storage_buffer) ||
						(resource.name == "push_constants_block" && resource.kind == rsx::mtl::resource_kind::push_constant) ||
						(resource.name == "VertexContextBuffer" && resource.kind == rsx::mtl::resource_kind::uniform_buffer) ||
						(resource.name == "VertexConstantsBuffer" && resource.kind == rsx::mtl::resource_kind::uniform_buffer);
				}
				else if (shader.metadata.stage == rsx::mtl::shader_stage::fragment)
				{
					supported =
						(resource.name == "FragmentConstantsBuffer" && resource.kind == rsx::mtl::resource_kind::uniform_buffer) ||
						(resource.name == "FragmentStateBuffer" && resource.kind == rsx::mtl::resource_kind::uniform_buffer) ||
						(resource.name == "TextureParametersBuffer" && resource.kind == rsx::mtl::resource_kind::uniform_buffer) ||
						(resource.name == "RasterizerHeap" && resource.kind == rsx::mtl::resource_kind::storage_buffer);
				}

				if (!supported)
				{
					error = "Translated Metal shader uses unsupported active resource '" + resource.name + "'";
					return false;
				}
				if ((resource.kind == rsx::mtl::resource_kind::texel_buffer &&
					 resource.msl_texture == rsx::mtl::invalid_binding) ||
					(resource.kind != rsx::mtl::resource_kind::texel_buffer &&
					 resource.msl_buffer == rsx::mtl::invalid_binding))
				{
					error = "Translated Metal shader resource '" + resource.name + "' has no assigned Metal slot";
					return false;
				}
			}
			return true;
		}

		bool allocate_upload(
			usz size,
			usz alignment,
			upload_allocation& allocation,
			std::string& error)
		{
			if (!m_uploads->allocate(m_frame_index, size, alignment, allocation, error))
			{
				return false;
			}
			std::memset(allocation.cpu_address, 0, allocation.size);
			return true;
		}

		metal_texture_ref make_texel_buffer_view(
			const upload_allocation& allocation,
			NSString* label,
			std::string& error)
		{
			metal_buffer_ref buffer = (__bridge metal_buffer_ref)allocation.native_buffer;
			if (!buffer || allocation.offset + allocation.size > buffer.length)
			{
				error = "Metal texel-buffer upload lies outside its backing page";
				return nil;
			}

			constexpr MTLResourceOptions options =
				MTLResourceStorageModeShared |
				MTLResourceCPUCacheModeWriteCombined |
				MTLResourceHazardTrackingModeTracked;
			MTLTextureDescriptor* descriptor = [MTLTextureDescriptor
				textureBufferDescriptorWithPixelFormat:MTLPixelFormatR8Uint
										 width:allocation.size
								resourceOptions:options
									 usage:MTLTextureUsageShaderRead];
			metal_texture_ref texture = [buffer newTextureWithDescriptor:descriptor
												 offset:allocation.offset
											bytesPerRow:0];
			if (!texture)
			{
				error = "Metal could not create an R8Uint vertex texel-buffer view";
				return nil;
			}
			texture.label = label;
			return texture;
		}

		bool prepare_draw_uploads(
			const draw_request& request,
			const rsx::mtl::rsx_shader_program& vertex_program,
			const rsx::mtl::rsx_shader_program& fragment_program,
			draw_uploads& uploads,
			std::string& error)
		{
			const auto* processor = request.renderer->draw_processor();
			if (!processor)
			{
				error = "RSX draw processor is unavailable";
				return false;
			}

			const usz texel_alignment = [m_device minimumTextureBufferAlignmentForPixelFormat:MTLPixelFormatR8Uint];
			if (!texel_alignment || (texel_alignment & (texel_alignment - 1)))
			{
				error = "Metal returned an invalid R8Uint texture-buffer alignment";
				return false;
			}
			const usz persistent_bytes = std::max<usz>(request.persistent_vertex_bytes, 16);
			const usz volatile_bytes = std::max<usz>(request.volatile_vertex_bytes, 16);
			if (!allocate_upload(persistent_bytes, texel_alignment, uploads.persistent_vertices, error) ||
				!allocate_upload(volatile_bytes, texel_alignment, uploads.volatile_vertices, error))
			{
				return false;
			}
			processor->write_vertex_data_to_memory(
				*request.vertex_layout,
				request.first,
				request.count,
				request.persistent_vertex_bytes ? uploads.persistent_vertices.cpu_address : nullptr,
				request.volatile_vertex_bytes ? uploads.volatile_vertices.cpu_address : nullptr);

			if (!allocate_upload(draw_parameters_bytes, 256, uploads.parameters, error))
			{
				return false;
			}
			auto* parameters = static_cast<draw_parameters*>(uploads.parameters.cpu_address);
			parameters->draw_id = request.subdraw_index;
			processor->fill_vertex_layout_state(
				*request.vertex_layout,
				request.renderer->current_vp_metadata,
				request.first,
				request.count,
				parameters->attrib_data,
				0,
				0);

			if (!allocate_upload(vertex_context_bytes, 256, uploads.vertex_context, error))
			{
				return false;
			}
			auto* vertex_context = static_cast<char*>(uploads.vertex_context.cpu_address);
			processor->fill_scale_offset_data(vertex_context, false);
			processor->fill_user_clip_data(vertex_context + 64);
			*reinterpret_cast<u32*>(vertex_context + 68) = rsx::method_registers.transform_branch_bits();
			*reinterpret_cast<f32*>(vertex_context + 72) =
				rsx::method_registers.point_size() * request.renderer->resolution_scaling_config.scale_factor();
			*reinterpret_cast<f32*>(vertex_context + 76) = rsx::method_registers.clip_min();
			*reinterpret_cast<f32*>(vertex_context + 80) = rsx::method_registers.clip_max();

			const usz vertex_constants_bytes = vertex_program.vertex_has_indexed_constants
				? 8192
				: vertex_program.vertex_constant_ids.size() * 16;
			if (!allocate_upload(std::max<usz>(vertex_constants_bytes, 16), 256, uploads.vertex_constants, error))
			{
				return false;
			}
			if (vertex_constants_bytes)
			{
				const std::span<const u16> relocation = vertex_program.vertex_has_indexed_constants
					? std::span<const u16>{}
					: std::span<const u16>(vertex_program.vertex_constant_ids);
				processor->fill_vertex_program_constants_data(
					uploads.vertex_constants.cpu_address, relocation);
			}

			const usz fragment_constants_bytes = request.renderer->current_fp_metadata.program_constants_buffer_length;
			if (!allocate_upload(std::max<usz>(fragment_constants_bytes, 16), 256, uploads.fragment_constants, error))
			{
				return false;
			}
			if (fragment_constants_bytes)
			{
				rsx::write_fragment_constants_to_buffer(
					std::span<f32>(
						static_cast<f32*>(uploads.fragment_constants.cpu_address),
						fragment_constants_bytes / sizeof(f32)),
					*request.fragment_program,
					fragment_program.fragment_constant_offsets,
					true);
			}

			if (!allocate_upload(fragment_context_bytes, 256, uploads.fragment_context, error) ||
				!allocate_upload(texture_parameters_bytes, 256, uploads.texture_parameters, error) ||
				!allocate_upload(rasterizer_heap_bytes, 256, uploads.rasterizer_heap, error))
			{
				return false;
			}
			processor->fill_fragment_state_buffer(
				uploads.fragment_context.cpu_address, *request.fragment_program);
			request.fragment_program->texture_params.write_to(
				uploads.texture_parameters.cpu_address,
				request.renderer->current_fp_metadata.referenced_textures_mask);

			uploads.persistent_vertex_view = make_texel_buffer_view(
				uploads.persistent_vertices, @"ARMSX3 persistent vertex stream", error);
			if (!uploads.persistent_vertex_view)
			{
				return false;
			}
			uploads.volatile_vertex_view = make_texel_buffer_view(
				uploads.volatile_vertices, @"ARMSX3 volatile vertex stream", error);
			return uploads.volatile_vertex_view != nil;
		}

		void bind_vertex_resources(
			metal_render_encoder_ref encoder,
			const rsx::mtl::translated_shader& shader,
			const draw_uploads& uploads) const
		{
			const u32 draw_parameters_offset = 0;
			for (const auto& translated : shader.resources)
			{
				if (!translated.active)
				{
					continue;
				}
				const auto& resource = translated.binding;
				if (resource.name == "persistent_input_stream")
				{
					[encoder setVertexTexture:uploads.persistent_vertex_view atIndex:resource.msl_texture];
				}
				else if (resource.name == "volatile_input_stream")
				{
					[encoder setVertexTexture:uploads.volatile_vertex_view atIndex:resource.msl_texture];
				}
				else if (resource.name == "DrawParametersBuffer")
				{
					[encoder setVertexBuffer:(__bridge metal_buffer_ref)uploads.parameters.native_buffer
								 offset:uploads.parameters.offset atIndex:resource.msl_buffer];
				}
				else if (resource.name == "push_constants_block")
				{
					[encoder setVertexBytes:&draw_parameters_offset length:sizeof(draw_parameters_offset) atIndex:resource.msl_buffer];
				}
				else if (resource.name == "VertexContextBuffer")
				{
					[encoder setVertexBuffer:(__bridge metal_buffer_ref)uploads.vertex_context.native_buffer
								 offset:uploads.vertex_context.offset atIndex:resource.msl_buffer];
				}
				else if (resource.name == "VertexConstantsBuffer")
				{
					[encoder setVertexBuffer:(__bridge metal_buffer_ref)uploads.vertex_constants.native_buffer
								 offset:uploads.vertex_constants.offset atIndex:resource.msl_buffer];
				}
			}
		}

		void bind_fragment_resources(
			metal_render_encoder_ref encoder,
			const rsx::mtl::translated_shader& shader,
			const draw_uploads& uploads) const
		{
			for (const auto& translated : shader.resources)
			{
				if (!translated.active)
				{
					continue;
				}
				const auto& resource = translated.binding;
				const upload_allocation* allocation = nullptr;
				if (resource.name == "FragmentConstantsBuffer") allocation = &uploads.fragment_constants;
				else if (resource.name == "FragmentStateBuffer") allocation = &uploads.fragment_context;
				else if (resource.name == "TextureParametersBuffer") allocation = &uploads.texture_parameters;
				else if (resource.name == "RasterizerHeap") allocation = &uploads.rasterizer_heap;
				if (allocation)
				{
					[encoder setFragmentBuffer:(__bridge metal_buffer_ref)allocation->native_buffer
								   offset:allocation->offset atIndex:resource.msl_buffer];
				}
			}
		}

		bool validate_context(const command_context& context, std::string& error) const
		{
			if (!m_device || !context.device || context.device != (__bridge void*)m_device)
			{
				error = "Metal command context belongs to a different or missing device";
				return false;
			}
			if (!context.command_buffer)
			{
				error = "Metal command context has no command buffer";
				return false;
			}
			id candidate = (__bridge id)context.command_buffer;
			if (![candidate conformsToProtocol:@protocol(MTLCommandBuffer)])
			{
				error = "Native command object does not conform to MTLCommandBuffer";
				return false;
			}
			return true;
		}

		bool validate_open_frame(const command_context& context, std::string& error) const
		{
			if (!m_frame_open || context.frame_index != m_frame_index)
			{
				error = "Metal command context does not match the open guest frame";
				return false;
			}
			return validate_context(context, error);
		}

		metal_texture_ref make_texture(
			MTLPixelFormat pixel_format,
			u32 width,
			u32 height,
			u32 samples,
			MTLTextureUsage usage,
			NSString* label,
			std::string& error)
		{
			MTLTextureDescriptor* descriptor = [MTLTextureDescriptor
				texture2DDescriptorWithPixelFormat:pixel_format
											 width:width
											height:height
										 mipmapped:NO];
			descriptor.storageMode = MTLStorageModePrivate;
			descriptor.usage = usage;
			if (samples > 1)
			{
				descriptor.textureType = MTLTextureType2DMultisample;
				descriptor.sampleCount = samples;
			}

			metal_texture_ref texture = [m_device newTextureWithDescriptor:descriptor];
			if (!texture)
			{
				error = "Metal could not allocate an RSX texture (format " +
				        std::to_string(static_cast<u64>(pixel_format)) + ", " +
				        std::to_string(width) + "x" + std::to_string(height) + ", " +
				        std::to_string(samples) + " samples)";
				return nil;
			}
			texture.label = label;
			return texture;
		}

		color_target* prepare_color_target(
			u32 address,
			u32 pitch,
			u32 width,
			u32 height,
			u32 samples,
			rsx::surface_color_format format,
			std::string& error)
		{
			const MTLPixelFormat pixel_format = color_pixel_format(format);
			if (pixel_format == MTLPixelFormatInvalid)
			{
				error = "Unsupported RSX color target format " + std::to_string(static_cast<u32>(format));
				return nullptr;
			}

			auto& slot = m_color_targets[address];
			if (!slot || !slot->matches(pitch, width, height, samples, format, pixel_format))
			{
				auto replacement = std::make_unique<color_target>();
				replacement->address = address;
				replacement->pitch = pitch;
				replacement->width = width;
				replacement->height = height;
				replacement->samples = samples;
				replacement->format = format;
				replacement->pixel_format = pixel_format;

				NSString* label = [NSString stringWithFormat:@"ARMSX3 RSX color 0x%08x", address];
				replacement->texture = make_texture(
					pixel_format,
					width,
					height,
					samples,
					MTLTextureUsageRenderTarget | (samples == 1 ? MTLTextureUsageShaderRead : 0),
					label,
					error);
				if (!replacement->texture)
				{
					return nullptr;
				}

				if (samples > 1)
				{
					replacement->resolve_texture = make_texture(
						pixel_format,
						width,
						height,
						1,
						MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead,
						[NSString stringWithFormat:@"ARMSX3 RSX color resolve 0x%08x", address],
						error);
					if (!replacement->resolve_texture)
					{
						return nullptr;
					}
				}

				slot = std::move(replacement);
			}

			slot->last_used_frame = m_frame_index;
			return slot.get();
		}

		depth_target* prepare_depth_target(
			u32 address,
			u32 pitch,
			u32 width,
			u32 height,
			u32 samples,
			rsx::surface_depth_format2 format,
			std::string& error)
		{
			const MTLPixelFormat pixel_format = depth_pixel_format(format);
			if (pixel_format == MTLPixelFormatInvalid)
			{
				error = "Unsupported RSX depth target format " + std::to_string(static_cast<u32>(format));
				return nullptr;
			}

			auto& slot = m_depth_targets[address];
			if (!slot || !slot->matches(pitch, width, height, samples, format, pixel_format))
			{
				auto replacement = std::make_unique<depth_target>();
				replacement->address = address;
				replacement->pitch = pitch;
				replacement->width = width;
				replacement->height = height;
				replacement->samples = samples;
				replacement->format = format;
				replacement->pixel_format = pixel_format;
				replacement->texture = make_texture(
					pixel_format,
					width,
					height,
					samples,
					MTLTextureUsageRenderTarget,
					[NSString stringWithFormat:@"ARMSX3 RSX depth 0x%08x", address],
					error);
				if (!replacement->texture)
				{
					return nullptr;
				}

				slot = std::move(replacement);
			}

			slot->last_used_frame = m_frame_index;
			return slot.get();
		}

		id<MTLRenderPipelineState> present_pipeline_for(MTLPixelFormat format, std::string& error)
		{
			auto& slot = m_present_pipelines[static_cast<u64>(format)];
			if (slot && slot->state)
			{
				return slot->state;
			}

			MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
			descriptor.label = @"ARMSX3 native RSX presentation pipeline";
			descriptor.vertexFunction = m_present_vertex;
			descriptor.fragmentFunction = m_present_fragment;
			descriptor.colorAttachments[0].pixelFormat = format;

			NSError* pipeline_error = nil;
			id<MTLRenderPipelineState> pipeline = [m_device
				newRenderPipelineStateWithDescriptor:descriptor
											   error:&pipeline_error];
			if (!pipeline)
			{
				error = metal_error(pipeline_error, "Metal failed to create the guest presentation pipeline");
				return nil;
			}

			slot = std::make_unique<present_pipeline>();
			slot->state = pipeline;
			return slot->state;
		}

		template <typename Map>
		void trim_map(Map& map)
		{
			for (auto iterator = map.begin(); iterator != map.end();)
			{
				if (m_frame_index > iterator->second->last_used_frame + target_retirement_age)
				{
					iterator = map.erase(iterator);
				}
				else
				{
					++iterator;
				}
			}

			while (map.size() > target_cache_limit)
			{
				auto oldest = map.begin();
				for (auto iterator = std::next(map.begin()); iterator != map.end(); ++iterator)
				{
					if (iterator->second->last_used_frame < oldest->second->last_used_frame)
					{
						oldest = iterator;
					}
				}
				map.erase(oldest);
			}
		}

		void trim_target_cache()
		{
			trim_map(m_color_targets);
			trim_map(m_depth_targets);
		}

		__strong metal_device_ref m_device = nil;
		__strong id<MTLLibrary> m_present_library = nil;
		__strong id<MTLFunction> m_present_vertex = nil;
		__strong id<MTLFunction> m_present_fragment = nil;
		__strong id<MTLSamplerState> m_present_sampler = nil;

		std::unordered_map<u32, std::unique_ptr<color_target>> m_color_targets;
		std::unordered_map<u32, std::unique_ptr<depth_target>> m_depth_targets;
		std::unordered_map<u64, std::unique_ptr<present_pipeline>> m_present_pipelines;
		vertex_spirv_cache m_vertex_spirv;
		fragment_spirv_cache m_fragment_spirv;
		std::unique_ptr<rsx::mtl::native_shader_cache> m_shader_cache;
		std::unique_ptr<upload_arena> m_uploads;
		std::array<color_target*, 4> m_active_colors{};
		depth_target* m_active_depth = nullptr;
		u64 m_frame_index = 0;
		u32 m_framebuffer_width = 0;
		u32 m_framebuffer_height = 0;
		u32 m_framebuffer_samples = 1;
		bool m_compiler_initialized = false;
		bool m_frame_open = false;
	};

	std::unique_ptr<guest_backend> make_native_guest_backend()
	{
		return std::make_unique<native_guest_backend>();
	}
} // namespace mtl
