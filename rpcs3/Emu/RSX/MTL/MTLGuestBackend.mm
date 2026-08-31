#include "MTLGuestBackend.h"

#include "Emu/RSX/Common/TextureUtils.h"
#include "Emu/RSX/Common/surface_store.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <string>
#include <unordered_map>
#include <utility>

namespace
{
	using metal_device_ref = id<MTLDevice>;
	using metal_command_buffer_ref = id<MTLCommandBuffer>;
	using metal_texture_ref = id<MTLTexture>;

	constexpr u64 target_retirement_age = 180;
	constexpr usz target_cache_limit = 96;

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
			const draw_request&,
			std::string& error) override
		{
			if (!validate_open_frame(context, error))
			{
				return false;
			}

			error = "RSX shader, resource, and draw binding is not implemented yet";
			return false;
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

			m_active_colors.fill(nullptr);
			m_active_depth = nullptr;
			m_frame_open = false;
			trim_target_cache();
			return true;
		}

		void abandon_frame(u64 frame_index) noexcept override
		{
			if (m_frame_open && frame_index == m_frame_index)
			{
				m_active_colors.fill(nullptr);
				m_active_depth = nullptr;
				m_frame_open = false;
			}
		}

		void shutdown() noexcept override
		{
			m_active_colors.fill(nullptr);
			m_active_depth = nullptr;
			m_color_targets.clear();
			m_depth_targets.clear();
			m_present_pipelines.clear();
			m_present_sampler = nil;
			m_present_vertex = nil;
			m_present_fragment = nil;
			m_present_library = nil;
			m_device = nil;
			m_frame_open = false;
		}

	private:
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
		std::array<color_target*, 4> m_active_colors{};
		depth_target* m_active_depth = nullptr;
		u64 m_frame_index = 0;
		u32 m_framebuffer_width = 0;
		u32 m_framebuffer_height = 0;
		bool m_frame_open = false;
	};

	std::unique_ptr<guest_backend> make_native_guest_backend()
	{
		return std::make_unique<native_guest_backend>();
	}
} // namespace mtl
