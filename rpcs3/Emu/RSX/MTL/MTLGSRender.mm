#include "MTLGSRender.h"

#include "Emu/System.h"
#include "Emu/RSX/NV47/HW/context_accessors.define.h"
#include "Emu/RSX/rsx_methods.h"
#include "Utilities/StrFmt.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <atomic>
#include <mutex>
#include <utility>

namespace
{
	using metal_device_ref = id<MTLDevice>;
	using metal_command_queue_ref = id<MTLCommandQueue>;
	using metal_command_buffer_ref = id<MTLCommandBuffer>;
	using metal_drawable_ref = id<CAMetalDrawable>;

	std::atomic<mtl::guest_backend_factory> g_guest_backend_factory{nullptr};

	struct async_error_state
	{
		std::mutex mutex;
		std::string error;
	};

	std::string objc_error(NSString* message, std::string_view fallback)
	{
		if (const char* text = message.UTF8String)
		{
			return text;
		}

		return std::string(fallback);
	}
}

namespace mtl
{
	void register_guest_backend_factory(guest_backend_factory factory) noexcept
	{
		g_guest_backend_factory.store(factory, std::memory_order_release);
	}
}

struct MTLGSRender::impl
{
	CAMetalLayer* layer = nil;
	metal_device_ref device = nil;
	metal_command_queue_ref queue = nil;
	metal_command_buffer_ref command_buffer = nil;
	metal_drawable_ref drawable = nil;

	std::unique_ptr<mtl::guest_backend> guest;
	std::shared_ptr<async_error_state> async_errors = std::make_shared<async_error_state>();
	u64 frame_index = 1;
	bool frame_open = false;
};

u64 MTLGSRender::get_cycles()
{
	return thread_ctrl::get_cycles(static_cast<named_thread<MTLGSRender>&>(*this));
}

MTLGSRender::MTLGSRender(utils::serial* ar) noexcept
	: GSRender(ar)
	, m_impl(std::make_unique<impl>())
{
	// Capabilities stay false until the corresponding Metal module is real.
	backend_config = {};
}

MTLGSRender::~MTLGSRender()
{
	abandon_frame();
	if (m_impl && m_impl->guest)
	{
		m_impl->guest->shutdown();
		m_impl->guest.reset();
	}

	if (m_frame)
	{
		m_frame->reset();
	}
}

[[noreturn]] void MTLGSRender::fail_closed(std::string_view operation, std::string_view detail)
{
	fmt::throw_exception("Native Metal RSX %s failed closed: %s", operation, detail);
}

mtl::command_context MTLGSRender::current_command_context() const
{
	return
	{
		.device = (__bridge void*)m_impl->device,
		.command_buffer = (__bridge void*)m_impl->command_buffer,
		.frame_index = m_impl->frame_index,
	};
}

void MTLGSRender::on_init_thread()
{
	GSRender::on_init_thread();

	std::string error;
	@autoreleasepool
	{
		@try
		{
			if (!m_frame || !m_frame->handle())
			{
				error = "no iOS display surface is attached";
			}
			else
			{
				CAMetalLayer* layer = (__bridge CAMetalLayer*)m_frame->handle();
				if (![layer isKindOfClass:CAMetalLayer.class])
				{
					error = "the display surface is not a CAMetalLayer";
				}
				else if (!layer.device)
				{
					error = "the CAMetalLayer has no MTLDevice";
				}
				else
				{
					m_impl->layer = layer;
					m_impl->device = layer.device;
					m_impl->queue = [m_impl->device newCommandQueue];
					if (!m_impl->queue)
					{
						error = "MTLDevice could not create a command queue";
					}
					else
					{
						m_impl->queue.label = @"ARMSX3 native Metal RSX queue";
					}
				}
			}
		}
		@catch (NSException* exception)
		{
			error = objc_error(exception.reason, "Objective-C exception during Metal initialization");
		}
	}

	if (!error.empty())
	{
		fail_closed("initialization", error);
	}

	const auto factory = g_guest_backend_factory.load(std::memory_order_acquire);
	if (!factory)
	{
		fail_closed("initialization", "no guest resource/shader backend is registered");
	}

	m_impl->guest = factory();
	if (!m_impl->guest)
	{
		fail_closed("initialization", "the guest backend factory returned null");
	}

	const mtl::device_context context
	{
		.device = (__bridge void*)m_impl->device,
		.registry_id = m_impl->device.registryID,
		.max_buffer_length = m_impl->device.maxBufferLength,
		.drawable_pixel_format = static_cast<u32>(m_impl->layer.pixelFormat),
		.unified_memory = m_impl->device.hasUnifiedMemory,
	};

	if (!m_impl->guest->initialize(context, error))
	{
		m_impl->guest->shutdown();
		m_impl->guest.reset();
		fail_closed("guest backend initialization", error.empty() ? "unspecified backend error" : error);
	}

	m_viewport.width = static_cast<double>(std::max(1, m_frame->client_width()));
	m_viewport.height = static_cast<double>(std::max(1, m_frame->client_height()));
	m_scissor.width = static_cast<u32>(m_viewport.width);
	m_scissor.height = static_cast<u32>(m_viewport.height);

	// rsx::thread owns this unique_ptr, while this renderer owns the object.
	// Match GL/Vulkan and release the pointer before destruction in on_exit().
	zcull_ctrl.reset(static_cast<rsx::reports::ZCULL_control*>(this));
}

void MTLGSRender::on_exit()
{
	GSRender::on_exit();
	abandon_frame();

	if (m_impl->guest)
	{
		m_impl->guest->shutdown();
		m_impl->guest.reset();
	}

	m_impl->queue = nil;
	m_impl->device = nil;
	m_impl->layer = nil;
	zcull_ctrl.release();
}

void MTLGSRender::ensure_frame()
{
	std::string async_error;
	{
		std::lock_guard lock(m_impl->async_errors->mutex);
		async_error = std::exchange(m_impl->async_errors->error, {});
	}

	if (!async_error.empty())
	{
		fail_closed("asynchronous command buffer", async_error);
	}

	if (m_impl->command_buffer)
	{
		return;
	}

	if (!m_impl->guest || !m_impl->queue)
	{
		fail_closed("frame begin", "renderer initialization is incomplete");
	}

	@autoreleasepool
	{
		@try
		{
			m_impl->command_buffer = [m_impl->queue commandBuffer];
			m_impl->command_buffer.label = [NSString stringWithFormat:
				@"ARMSX3 RSX frame %llu", static_cast<unsigned long long>(m_impl->frame_index)];
		}
		@catch (NSException* exception)
		{
			fail_closed("frame begin", objc_error(exception.reason, "Metal command-buffer exception"));
		}
	}

	if (!m_impl->command_buffer)
	{
		fail_closed("frame begin", "MTLCommandQueue returned no command buffer");
	}

	std::string error;
	if (!m_impl->guest->begin_frame(current_command_context(), error))
	{
		m_impl->guest->abandon_frame(m_impl->frame_index);
		m_impl->command_buffer = nil;
		fail_closed("frame begin", error.empty() ? "unspecified backend error" : error);
	}

	m_impl->frame_open = true;
}

void MTLGSRender::update_viewport()
{
	const auto [width, height] = rsx::apply_resolution_scale<true>(
		resolution_scaling_config,
		rsx::method_registers.surface_clip_width(),
		rsx::method_registers.surface_clip_height());

	m_viewport.x = 0.;
	m_viewport.y = 0.;
	m_viewport.width = static_cast<double>(width);
	m_viewport.height = static_cast<double>(height);
	m_viewport.z_near = std::clamp<double>(rsx::method_registers.clip_min(), 0., 1.);
	m_viewport.z_far = std::clamp<double>(rsx::method_registers.clip_max(), 0., 1.);
}

void MTLGSRender::update_scissor(bool clip_viewport)
{
	areau region;
	if (!get_scissor(region, clip_viewport))
	{
		return;
	}

	const u32 max_width = std::max<u32>(1, m_framebuffer_layout.width);
	const u32 max_height = std::max<u32>(1, m_framebuffer_layout.height);
	m_scissor.x = std::min<u32>(region.x1, max_width);
	m_scissor.y = std::min<u32>(region.y1, max_height);
	m_scissor.width = std::min<u32>(region.width(), max_width - m_scissor.x);
	m_scissor.height = std::min<u32>(region.height(), max_height - m_scissor.y);
}

bool MTLGSRender::prepare_framebuffer(rsx::framebuffer_creation_context context)
{
	const bool unchanged = m_framebuffer_prepared &&
		m_current_framebuffer_context == context &&
		!m_graphics_state.test(rsx::rtt_config_dirty);
	if (unchanged)
	{
		update_viewport();
		update_scissor(context == rsx::framebuffer_creation_context::context_draw);
		return m_graphics_state.test(rsx::rtt_config_valid);
	}

	m_graphics_state.clear(
		rsx::rtt_config_dirty |
		rsx::rtt_config_contested |
		rsx::rtt_config_valid |
		rsx::rtt_cache_state_dirty |
		rsx::pipeline_config_dirty);

	get_framebuffer_layout(context, m_framebuffer_layout);
	if (!m_graphics_state.test(rsx::rtt_config_valid))
	{
		m_framebuffer_prepared = false;
		return false;
	}

	update_viewport();
	update_scissor(context == rsx::framebuffer_creation_context::context_draw);
	ensure_frame();

	std::string error;
	if (!m_impl->guest->prepare_framebuffer(
			current_command_context(), context, m_framebuffer_layout, error))
	{
		fail_closed("framebuffer preparation", error.empty() ? "unspecified backend error" : error);
	}

	m_framebuffer_prepared = true;
	on_framebuffer_layout_updated();
	return true;
}

void MTLGSRender::clear_surface(u32 mask)
{
	if (!rsx::method_registers.stencil_mask())
	{
		mask &= ~RSX_GCM_CLEAR_STENCIL_BIT;
	}

	if (!(mask & RSX_GCM_CLEAR_ANY_MASK))
	{
		return;
	}

	u8 creation_context = rsx::framebuffer_creation_context::context_draw;
	if (mask & RSX_GCM_CLEAR_COLOR_RGBA_MASK)
	{
		creation_context |= rsx::framebuffer_creation_context::context_clear_color;
	}
	if (mask & RSX_GCM_CLEAR_DEPTH_STENCIL_MASK)
	{
		creation_context |= rsx::framebuffer_creation_context::context_clear_depth;
	}

	if (!prepare_framebuffer(static_cast<rsx::framebuffer_creation_context>(creation_context)))
	{
		return;
	}

	const auto depth_format = rsx::method_registers.surface_depth_fmt();
	const u32 max_depth = get_max_depth_value(depth_format);
	const u32 raw_depth = rsx::method_registers.z_clear_value(is_depth_stencil_format(depth_format));
	const mtl::clear_request request
	{
		.framebuffer = &m_framebuffer_layout,
		.mask = mask,
		.color =
		{
			static_cast<float>(rsx::method_registers.clear_color_r()) / 255.f,
			static_cast<float>(rsx::method_registers.clear_color_g()) / 255.f,
			static_cast<float>(rsx::method_registers.clear_color_b()) / 255.f,
			static_cast<float>(rsx::method_registers.clear_color_a()) / 255.f,
		},
		.depth = max_depth ? static_cast<float>(raw_depth) / max_depth : 1.f,
		.stencil = rsx::method_registers.stencil_clear_value(),
		.stencil_write_mask = static_cast<u8>(rsx::method_registers.stencil_mask()),
		.viewport_state = m_viewport,
		.scissor = m_scissor,
	};

	std::string error;
	if (!m_impl->guest->encode_clear(current_command_context(), request, error))
	{
		fail_closed("guest clear", error.empty() ? "unspecified backend error" : error);
	}
}

void MTLGSRender::begin()
{
	rsx::thread::begin();
	if (skip_current_frame || cond_render_ctrl.disable_rendering())
	{
		return;
	}

	prepare_framebuffer(rsx::framebuffer_creation_context::context_draw);
}

void MTLGSRender::emit_geometry(u32 subdraw_index)
{
	auto& draw = rsx::method_registers.current_draw_clause;
	const u32 dependencies = subdraw_index == 0
		? rsx::vertex_arrays_changed
		: draw.execute_pipeline_dependencies(m_ctx);
	const auto& range = draw.get_range();

	const mtl::draw_request request
	{
		.renderer = this,
		.vertex_program = &current_vertex_program,
		.fragment_program = &current_fragment_program,
		.framebuffer = &m_framebuffer_layout,
		.primitive = draw.primitive,
		.command = draw.command,
		.subdraw_index = subdraw_index,
		.dependency_flags = dependencies,
		.first = range.first,
		.count = range.count,
		.instance_count = draw.is_trivial_instanced_draw ? draw.pass_count() : 1u,
		.indexed = draw.command == rsx::draw_command::indexed,
		.inline_vertices = draw.command == rsx::draw_command::inlined_array,
		.viewport_state = m_viewport,
		.scissor = m_scissor,
	};

	std::string error;
	if (!m_impl->guest->encode_draw(current_command_context(), request, error))
	{
		fail_closed("guest draw", error.empty() ? "unspecified backend error" : error);
	}
}

void MTLGSRender::end()
{
	if (skip_current_frame ||
		!m_graphics_state.test(rsx::rtt_config_valid) ||
		cond_render_ctrl.disable_rendering())
	{
		execute_nop_draw();
		rsx::thread::end();
		return;
	}

	ensure_frame();
	analyse_current_rsx_pipeline();

	auto& draw = rsx::method_registers.current_draw_clause;
	draw.begin();
	u32 subdraw = 0;
	do
	{
		emit_geometry(subdraw++);
	}
	while (draw.next());

	rsx::thread::end();
}

void MTLGSRender::abandon_frame() noexcept
{
	if (!m_impl || !m_impl->frame_open)
	{
		return;
	}

	if (m_impl->guest)
	{
		m_impl->guest->abandon_frame(m_impl->frame_index);
	}

	m_impl->drawable = nil;
	m_impl->command_buffer = nil;
	m_impl->frame_open = false;
}

void MTLGSRender::submit_frame(bool present)
{
	if (!m_impl->frame_open || !m_impl->command_buffer)
	{
		return;
	}

	std::string error;
	if (!m_impl->guest->finish_frame(current_command_context(), present, error))
	{
		abandon_frame();
		fail_closed("frame finalization", error.empty() ? "unspecified backend error" : error);
	}

	metal_command_buffer_ref command_buffer = m_impl->command_buffer;
	const auto state = m_impl->async_errors;
	const u64 frame_index = m_impl->frame_index;

	@autoreleasepool
	{
		@try
		{
			if (present)
			{
				[command_buffer presentDrawable:m_impl->drawable];
			}

			[command_buffer addCompletedHandler:^(metal_command_buffer_ref completed) {
				if (completed.status == MTLCommandBufferStatusError)
				{
					const std::string detail = objc_error(
						completed.error.localizedDescription,
						"unknown Metal command-buffer error");
					std::lock_guard lock(state->mutex);
					if (state->error.empty())
					{
						state->error = "frame " + std::to_string(frame_index) + ": " + detail;
					}
				}
			}];
			[command_buffer commit];
		}
		@catch (NSException* exception)
		{
			abandon_frame();
			fail_closed("frame submission", objc_error(exception.reason, "Metal submission exception"));
		}
	}

	m_impl->drawable = nil;
	m_impl->command_buffer = nil;
	m_impl->frame_open = false;
	m_impl->frame_index++;
}

void MTLGSRender::flip(const rsx::display_flip_info_t& info)
{
	if (info.skip_frame)
	{
		submit_frame(false);
		m_frame->flip(m_context, true);
		rsx::thread::flip(info);
		return;
	}

	ensure_frame();
	@autoreleasepool
	{
		@try
		{
			m_impl->drawable = [m_impl->layer nextDrawable];
		}
		@catch (NSException* exception)
		{
			abandon_frame();
			fail_closed("drawable acquisition", objc_error(exception.reason, "CAMetalLayer exception"));
		}
	}

	if (!m_impl->drawable)
	{
		abandon_frame();
		fail_closed("drawable acquisition", "CAMetalLayer returned no drawable");
	}

	u32 width = 0;
	u32 height = 0;
	u32 pitch = 0;
	u32 format = CELL_GCM_TEXTURE_A8R8G8B8;
	u32 address = 0;
	const bool valid_guest_buffer = info.buffer < display_buffers_count;
	if (valid_guest_buffer)
	{
		width = display_buffers[info.buffer].width;
		height = display_buffers[info.buffer].height;
		pitch = display_buffers[info.buffer].pitch;
		address = rsx::get_address(display_buffers[info.buffer].offset, CELL_GCM_LOCATION_LOCAL);
	}

	const auto& avconfig = g_fxo->get<rsx::avconf>();
	if (!width || !height)
	{
		width = avconfig.resolution_x;
		height = avconfig.resolution_y;
	}
	if (avconfig.state)
	{
		format = avconfig.get_compatible_gcm_format();
		if (!pitch)
		{
			pitch = width * avconfig.get_bpp();
		}
	}
	else if (!pitch)
	{
		pitch = width * 4;
	}

	const mtl::present_context present_context
	{
		.commands = current_command_context(),
		.drawable_texture = (__bridge void*)m_impl->drawable.texture,
		.drawable_width = static_cast<u32>(m_impl->drawable.texture.width),
		.drawable_height = static_cast<u32>(m_impl->drawable.texture.height),
		.drawable_pixel_format = static_cast<u32>(m_impl->drawable.texture.pixelFormat),
	};
	const mtl::present_request request
	{
		.buffer_index = info.buffer,
		.guest_address = address,
		.guest_format = format,
		.width = width,
		.height = height,
		.pitch = pitch,
		.valid_guest_buffer = valid_guest_buffer,
		.emulated_flip = info.emu_flip,
	};

	std::string error;
	if (!m_impl->guest->encode_present(present_context, request, error))
	{
		abandon_frame();
		fail_closed("guest presentation", error.empty() ? "unspecified backend error" : error);
	}

	submit_frame(true);
	m_frame->flip(m_context, false);
	rsx::thread::flip(info);
}

void MTLGSRender::write_barrier(u32, u32)
{
	fail_closed("memory barrier", "guest resource coherency is not implemented");
}

bool MTLGSRender::release_GCM_label(u32, u32, u32)
{
	fail_closed("GCM label release", "host-label synchronization is not implemented");
}

bool MTLGSRender::scaled_image_from_memory(
	const rsx::blit_src_info&,
	const rsx::blit_dst_info&,
	bool)
{
	fail_closed("scaled blit", "the Metal blit module is not implemented");
}

bool MTLGSRender::on_access_violation(u32, bool)
{
	fail_closed("memory fault", "guest texture-fault handling is not implemented");
}

void MTLGSRender::on_invalidate_memory_range(
	const utils::address_range32&,
	rsx::invalidation_cause)
{
	fail_closed("memory invalidation", "guest resource invalidation is not implemented");
}

void MTLGSRender::notify_tile_unbound(u32)
{
	fail_closed("tile unbind", "guest tiled-resource invalidation is not implemented");
}

void MTLGSRender::on_semaphore_acquire_wait()
{
	fail_closed("semaphore wait", "guest GPU semaphore synchronization is not implemented");
}

void MTLGSRender::begin_occlusion_query(rsx::reports::occlusion_query_info*)
{
	fail_closed("occlusion query begin", "the Metal query module is not implemented");
}

void MTLGSRender::end_occlusion_query(rsx::reports::occlusion_query_info*)
{
	fail_closed("occlusion query end", "the Metal query module is not implemented");
}

bool MTLGSRender::check_occlusion_query_status(rsx::reports::occlusion_query_info*)
{
	fail_closed("occlusion query status", "the Metal query module is not implemented");
}

void MTLGSRender::get_occlusion_query_result(rsx::reports::occlusion_query_info*)
{
	fail_closed("occlusion query result", "the Metal query module is not implemented");
}

void MTLGSRender::discard_occlusion_query(rsx::reports::occlusion_query_info*)
{
	fail_closed("occlusion query discard", "the Metal query module is not implemented");
}
