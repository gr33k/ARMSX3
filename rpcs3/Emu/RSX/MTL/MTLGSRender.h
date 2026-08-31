#pragma once

#include "Emu/RSX/GSRender.h"

#include <array>
#include <memory>
#include <string>
#include <string_view>

class MTLGSRender;

namespace mtl
{
	// Objective-C Metal objects are passed as unretained, call-scoped handles.
	// Implementations must bridge and retain a handle explicitly if it must outlive
	// the callback that supplied it.
	using native_handle = void*;

	struct viewport
	{
		double x = 0.;
		double y = 0.;
		double width = 0.;
		double height = 0.;
		double z_near = 0.;
		double z_far = 1.;
	};

	struct scissor_rect
	{
		u32 x = 0;
		u32 y = 0;
		u32 width = 0;
		u32 height = 0;
	};

	struct device_context
	{
		native_handle device = nullptr; // id<MTLDevice>
		u64 registry_id = 0;
		u64 max_buffer_length = 0;
		u32 drawable_pixel_format = 0;
		bool unified_memory = false;
	};

	struct command_context
	{
		native_handle device = nullptr;         // id<MTLDevice>
		native_handle command_buffer = nullptr; // id<MTLCommandBuffer>
		u64 frame_index = 0;
	};

	struct present_context
	{
		command_context commands{};
		native_handle drawable_texture = nullptr; // id<MTLTexture>
		u32 drawable_width = 0;
		u32 drawable_height = 0;
		u32 drawable_pixel_format = 0;
	};

	struct clear_request
	{
		const rsx::framebuffer_layout* framebuffer = nullptr;
		u32 mask = 0;
		std::array<float, 4> color{};
		float depth = 1.f;
		u8 stencil = 0;
		u8 stencil_write_mask = 0;
		viewport viewport_state{};
		scissor_rect scissor{};
	};

	struct draw_request
	{
		// These pointers are immutable and valid only for the synchronous callback.
		const rsx::thread* renderer = nullptr;
		const RSXVertexProgram* vertex_program = nullptr;
		const RSXFragmentProgram* fragment_program = nullptr;
		const rsx::framebuffer_layout* framebuffer = nullptr;

		rsx::primitive_type primitive{};
		rsx::draw_command command{};
		u32 subdraw_index = 0;
		u32 dependency_flags = 0;
		u32 first = 0;
		u32 count = 0;
		u32 instance_count = 1;
		bool indexed = false;
		bool inline_vertices = false;
		viewport viewport_state{};
		scissor_rect scissor{};
	};

	struct present_request
	{
		u32 buffer_index = 0;
		u32 guest_address = 0;
		u32 guest_format = 0;
		u32 width = 0;
		u32 height = 0;
		u32 pitch = 0;
		bool valid_guest_buffer = false;
		bool emulated_flip = false;
	};

	// The renderer owns the Metal device, queue, command buffers, drawable, and
	// submission lifecycle. This backend owns guest render targets, uploads,
	// shaders, pipelines, and synchronization. Every method is synchronous and
	// must leave no open MTLRenderCommandEncoder when it returns.
	class guest_backend
	{
	public:
		virtual ~guest_backend() = default;

		virtual bool initialize(const device_context& context, std::string& error) = 0;
		virtual bool begin_frame(const command_context& context, std::string& error) = 0;
		virtual bool prepare_framebuffer(
			const command_context& context,
			rsx::framebuffer_creation_context creation_context,
			const rsx::framebuffer_layout& layout,
			std::string& error) = 0;
		virtual bool encode_clear(
			const command_context& context,
			const clear_request& request,
			std::string& error) = 0;
		virtual bool encode_draw(
			const command_context& context,
			const draw_request& request,
			std::string& error) = 0;
		virtual bool encode_present(
			const present_context& context,
			const present_request& request,
			std::string& error) = 0;
		virtual bool finish_frame(
			const command_context& context,
			bool will_present,
			std::string& error) = 0;

		virtual void abandon_frame(u64 frame_index) noexcept = 0;
		virtual void shutdown() noexcept = 0;
	};

	using guest_backend_factory = std::unique_ptr<guest_backend> (*)();

	// Integration must register a complete guest backend before selecting Metal.
	// Passing nullptr removes the factory and makes initialization fail closed.
	void register_guest_backend_factory(guest_backend_factory factory) noexcept;
}

class MTLGSRender : public GSRender, public rsx::reports::ZCULL_control
{
public:
	MTLGSRender(utils::serial* ar) noexcept;
	MTLGSRender() noexcept : MTLGSRender(nullptr) {}
	~MTLGSRender() override;

	u64 get_cycles() final;

protected:
	void clear_surface(u32 mask) override;
	void begin() override;
	void end() override;
	void emit_geometry(u32 subdraw_index) override;

	void on_init_thread() override;
	void on_exit() override;
	void flip(const rsx::display_flip_info_t& info) override;

	// Resource-coherency, blit, and query modules are deliberately not faked.
	void write_barrier(u32 address, u32 range) override;
	bool release_GCM_label(u32 type, u32 address, u32 value) override;
	bool scaled_image_from_memory(
		const rsx::blit_src_info& src,
		const rsx::blit_dst_info& dst,
		bool interpolate) override;
	bool on_access_violation(u32 address, bool is_writing) override;
	void on_invalidate_memory_range(
		const utils::address_range32& range,
		rsx::invalidation_cause cause) override;
	void notify_tile_unbound(u32 tile) override;
	void on_semaphore_acquire_wait() override;

	void begin_occlusion_query(rsx::reports::occlusion_query_info* query) override;
	void end_occlusion_query(rsx::reports::occlusion_query_info* query) override;
	bool check_occlusion_query_status(rsx::reports::occlusion_query_info* query) override;
	void get_occlusion_query_result(rsx::reports::occlusion_query_info* query) override;
	void discard_occlusion_query(rsx::reports::occlusion_query_info* query) override;

private:
	struct impl;
	std::unique_ptr<impl> m_impl;

	mtl::viewport m_viewport{};
	mtl::scissor_rect m_scissor{};
	bool m_framebuffer_prepared = false;

	void ensure_frame();
	bool prepare_framebuffer(rsx::framebuffer_creation_context context);
	void update_viewport();
	void update_scissor(bool clip_viewport);
	void abandon_frame() noexcept;
	void submit_frame(bool present);
	mtl::command_context current_command_context() const;

	[[noreturn]] static void fail_closed(std::string_view operation, std::string_view detail);
};
