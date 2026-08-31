// SPDX-FileCopyrightText: 2026 ARMSX3 contributors
// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Architectural provenance: persistent Metal ownership, completion-timed command
// buffers, drawable lifetime, and draw/fence-tagged upload-ring concepts were
// adapted from ARMSX2's GSDeviceMTL at commit
// 1024c3538ee2ff27fc0f9d5272d76202b8b1c03b. This interface is an RSX-neutral
// implementation; it contains no PS2 GS draw, state, shader, or pipeline logic.

#pragma once

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <string_view>

namespace rsx::metal
{
	// Objective-C++ callers pass CAMetalLayer* with (__bridge void*). Handles
	// returned by this API are borrowed and valid only for the documented owner.
	using native_handle = void*;

	enum class error_code : std::uint8_t
	{
		none,
		invalid_argument,
		already_running,
		not_running,
		stopping,
		unsupported_device,
		resource_creation_failed,
		command_buffer_unavailable,
		drawable_unavailable,
		upload_ring_exhausted,
		timed_out,
		metal_exception,
	};

	struct error
	{
		error_code code = error_code::none;
		std::string message;

		explicit operator bool() const noexcept
		{
			return code != error_code::none;
		}
	};

	struct runtime_config
	{
		// Fixed-size shared/write-combined memory. Keeping this bounded avoids an
		// orphan-and-grow loop under iOS memory pressure.
		std::size_t upload_ring_bytes = 32u * 1024u * 1024u;
		std::uint32_t max_command_buffers_in_flight = 3;
		std::uint32_t completion_history_limit = 64;
	};

	enum class command_status : std::uint8_t
	{
		completed,
		failed,
		unknown,
	};

	struct command_completion
	{
		std::uint64_t fence_value = 0;
		command_status status = command_status::unknown;
		std::uint64_t cpu_submit_time_ns = 0;
		std::uint64_t cpu_complete_time_ns = 0;
		std::uint64_t gpu_start_time_ns = 0;
		std::uint64_t gpu_end_time_ns = 0;
		std::uint64_t gpu_duration_ns = 0;
		std::int64_t metal_error_code = 0;
		std::string metal_error_domain;
		std::string metal_error_message;
	};

	struct telemetry_snapshot
	{
		std::uint64_t command_buffers_started = 0;
		std::uint64_t command_buffers_submitted = 0;
		std::uint64_t command_buffers_completed = 0;
		std::uint64_t command_buffers_failed = 0;
		std::uint64_t command_buffers_abandoned = 0;
		std::uint64_t drawable_acquisitions = 0;
		std::uint64_t drawable_misses = 0;
		std::uint64_t accumulated_gpu_time_ns = 0;
		std::uint64_t last_completed_fence = 0;
		std::uint32_t active_command_buffers = 0;
		std::uint32_t peak_active_command_buffers = 0;
		std::size_t upload_ring_capacity = 0;
		std::size_t upload_ring_bytes_in_use = 0;
		std::size_t upload_ring_peak_bytes_in_use = 0;
		std::uint64_t upload_allocations = 0;
		std::uint64_t upload_bytes = 0;
		std::uint64_t upload_wait_count = 0;
		std::uint64_t upload_wait_time_ns = 0;
		std::uint64_t upload_timeout_count = 0;
		bool stopping = false;
	};

	struct upload_slice
	{
		// buffer and cpu_address remain valid until the command context is
		// abandoned or its returned fence completes. The bytes may be reused
		// immediately after that point.
		native_handle buffer = nullptr;
		std::byte* cpu_address = nullptr;
		std::size_t offset = 0;
		std::size_t size = 0;
		std::uint64_t reservation_id = 0;
	};

	class command_context final
	{
	public:
		command_context() noexcept;
		~command_context();
		command_context(command_context&&) noexcept;
		command_context& operator=(command_context&&) noexcept;

		command_context(const command_context&) = delete;
		command_context& operator=(const command_context&) = delete;

		explicit operator bool() const noexcept;
		native_handle native_command_buffer() const noexcept;
		std::uint64_t owner_id() const noexcept;

	private:
		struct impl;
		std::unique_ptr<impl> m_impl;

		friend class runtime;
	};

	class drawable final
	{
	public:
		drawable() noexcept;
		~drawable();
		drawable(drawable&&) noexcept;
		drawable& operator=(drawable&&) noexcept;

		drawable(const drawable&) = delete;
		drawable& operator=(const drawable&) = delete;

		explicit operator bool() const noexcept;
		native_handle native_drawable() const noexcept;
		native_handle texture() const noexcept;
		std::uint32_t width() const noexcept;
		std::uint32_t height() const noexcept;

	private:
		struct impl;
		std::unique_ptr<impl> m_impl;

		friend class runtime;
	};

	enum class stop_result : std::uint8_t
	{
		not_running,
		drained,
		deferred,
	};

	class runtime final
	{
	public:
		runtime();
		~runtime();
		runtime(runtime&&) noexcept;
		runtime& operator=(runtime&&) noexcept;

		runtime(const runtime&) = delete;
		runtime& operator=(const runtime&) = delete;

		// The CAMetalLayer must already have its permanent MTLDevice and drawable
		// properties configured by the iOS view on the main thread.
		bool start(native_handle metal_layer, const runtime_config& config, error* out_error = nullptr);

		// Stop rejects new work immediately. Drained means all open/submitted work
		// released its slot and native ownership was torn down synchronously.
		// Deferred is still memory-safe: command completion/context destruction
		// retains the state until its final GPU/user lifetime ends.
		stop_result stop(std::chrono::milliseconds timeout = std::chrono::seconds(2)) noexcept;

		bool running() const noexcept;
		native_handle device() const noexcept;
		native_handle command_queue() const noexcept;

		bool begin_command_buffer(
			command_context& out_context,
			std::string_view label,
			std::chrono::milliseconds timeout,
			error* out_error = nullptr);

		// A drawable is tied to one command context, which prevents more drawable
		// ownership than the bounded command-buffer window.
		bool acquire_drawable(
			command_context& context,
			drawable& out_drawable,
			error* out_error = nullptr);

		bool allocate_upload(
			command_context& context,
			std::size_t size,
			std::size_t alignment,
			std::chrono::milliseconds timeout,
			upload_slice& out_slice,
			error* out_error = nullptr);

		bool present(command_context& context, drawable&& frame, error* out_error = nullptr);

		// On success, fence_value is a process-local monotonically increasing GPU
		// completion value. Upload ranges owned by this context are reclaimed only
		// after this fence's completion callback runs.
		bool commit(command_context&& context, std::uint64_t& fence_value, error* out_error = nullptr);
		void abandon(command_context&& context) noexcept;

		bool wait_for_fence(std::uint64_t fence_value, std::chrono::milliseconds timeout) const noexcept;
		bool poll_completion(command_completion& out_completion);
		telemetry_snapshot telemetry() const noexcept;

	private:
		struct impl;
		std::unique_ptr<impl> m_impl;
	};
}
