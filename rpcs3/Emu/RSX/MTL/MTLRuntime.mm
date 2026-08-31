// SPDX-FileCopyrightText: 2026 ARMSX3 contributors
// SPDX-FileCopyrightText: 2002-2026 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Architectural provenance: persistent Metal ownership, completion-timed command
// buffers, drawable lifetime, and draw/fence-tagged upload-ring concepts were
// adapted from ARMSX2's GSDeviceMTL at commit
// 1024c3538ee2ff27fc0f9d5272d76202b8b1c03b. This is a clean RSX runtime layer;
// no PS2 GS renderer logic is present.

#include "MTLRuntime.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <condition_variable>
#include <deque>
#include <limits>
#include <mutex>
#include <unordered_set>
#include <utility>

namespace rsx::metal
{
namespace
{
	using steady_clock = std::chrono::steady_clock;
	constexpr std::size_t ring_granularity = 64u * 1024u;
	constexpr std::size_t maximum_upload_alignment = ring_granularity;
	constexpr std::uint32_t maximum_in_flight_limit = 8;
	constexpr std::uint32_t maximum_completion_history = 1024;

	void clear_error(error* out_error)
	{
		if (out_error)
		{
			out_error->code = error_code::none;
			out_error->message.clear();
		}
	}

	bool fail(error* out_error, error_code code, std::string message)
	{
		if (out_error)
		{
			out_error->code = code;
			out_error->message = std::move(message);
		}
		return false;
	}

	std::string utf8_string(NSString* value)
	{
		const char* text = value.UTF8String;
		return text ? text : "";
	}

	std::uint64_t monotonic_time_ns() noexcept
	{
		return static_cast<std::uint64_t>(
			std::chrono::duration_cast<std::chrono::nanoseconds>(
				steady_clock::now().time_since_epoch()).count());
	}

	std::uint64_t seconds_to_ns(double seconds) noexcept
	{
		if (!(seconds > 0.0))
			return 0;

		constexpr double maximum = static_cast<double>(std::numeric_limits<std::uint64_t>::max());
		const double nanoseconds = seconds * 1'000'000'000.0;
		return nanoseconds >= maximum ? std::numeric_limits<std::uint64_t>::max()
			: static_cast<std::uint64_t>(nanoseconds);
	}

	bool is_power_of_two(std::size_t value) noexcept
	{
		return value && !(value & (value - 1));
	}

	bool round_up(std::size_t value, std::size_t alignment, std::size_t& result) noexcept
	{
		if (!is_power_of_two(alignment) || value > std::numeric_limits<std::size_t>::max() - (alignment - 1))
			return false;
		result = (value + alignment - 1) & ~(alignment - 1);
		return true;
	}

	class objc_ref final
	{
	public:
		objc_ref() noexcept = default;

		explicit objc_ref(id object) noexcept
		{
			reset(object);
		}

		objc_ref(const objc_ref& other) noexcept
		{
			if (other.m_object)
				m_object = const_cast<void*>(reinterpret_cast<const void*>(CFRetain(static_cast<CFTypeRef>(other.m_object))));
		}

		objc_ref& operator=(const objc_ref& other) noexcept
		{
			if (this != &other)
			{
				objc_ref copy(other);
				swap(copy);
			}
			return *this;
		}

		objc_ref(objc_ref&& other) noexcept
			: m_object(std::exchange(other.m_object, nullptr))
		{
		}

		objc_ref& operator=(objc_ref&& other) noexcept
		{
			if (this != &other)
			{
				clear();
				m_object = std::exchange(other.m_object, nullptr);
			}
			return *this;
		}

		~objc_ref()
		{
			clear();
		}

		void reset(id object = nil) noexcept
		{
			void* replacement = object
				? const_cast<void*>(reinterpret_cast<const void*>(CFRetain((__bridge CFTypeRef)object)))
				: nullptr;
			clear();
			m_object = replacement;
		}

		void clear() noexcept
		{
			if (m_object)
			{
				CFRelease(static_cast<CFTypeRef>(m_object));
				m_object = nullptr;
			}
		}

		void swap(objc_ref& other) noexcept
		{
			std::swap(m_object, other.m_object);
		}

		void* get() const noexcept
		{
			return m_object;
		}

		explicit operator bool() const noexcept
		{
			return m_object != nullptr;
		}

	private:
		void* m_object = nullptr;
	};

	void release_created_object(id object) noexcept
	{
#if !__has_feature(objc_arc)
		[object release];
#else
		(void)object;
#endif
	}

	class upload_ring final
	{
	public:
		struct allocation
		{
			upload_slice slice;
			bool waited = false;
			std::uint64_t wait_time_ns = 0;
		};

		struct snapshot
		{
			std::size_t capacity = 0;
			std::size_t bytes_in_use = 0;
			std::size_t peak_bytes_in_use = 0;
			std::uint64_t allocations = 0;
			std::uint64_t bytes = 0;
			std::uint64_t wait_count = 0;
			std::uint64_t wait_time_ns = 0;
			std::uint64_t timeout_count = 0;
		};

		upload_ring(objc_ref buffer, std::byte* contents, std::size_t capacity) noexcept
			: m_buffer(std::move(buffer))
			, m_contents(contents)
			, m_capacity(capacity)
		{
		}

		bool allocate(
			std::uint64_t owner,
			std::size_t size,
			std::size_t alignment,
			std::chrono::milliseconds timeout,
			allocation& out,
			error* out_error)
		{
			const auto wait_started = steady_clock::now();
			bool waited = false;
			std::unique_lock lock(m_mutex);

			if (size == 0 || size > m_capacity)
				return fail(out_error, error_code::invalid_argument, "Upload size is zero or exceeds the fixed ring capacity");
			if (!is_power_of_two(alignment) || alignment > maximum_upload_alignment)
				return fail(out_error, error_code::invalid_argument, "Upload alignment must be a power of two no larger than 64 KiB");

			const bool wait_forever = timeout == std::chrono::milliseconds::max();
			const auto deadline = wait_forever ? steady_clock::time_point::max() : wait_started + timeout;

			for (;;)
			{
				reclaim_locked();
				if (m_stopping)
					return fail(out_error, error_code::stopping, "Metal upload ring is stopping");

				// Once every earlier lifetime is reclaimed, restart at a physical
				// buffer boundary. This prevents an empty ring from losing capacity
				// to a wrap/alignment gap.
				if (m_records.empty())
				{
					const std::uint64_t remainder = m_write_cursor % m_capacity;
					if (remainder)
						m_write_cursor += m_capacity - remainder;
					m_reclaim_cursor = m_write_cursor;
				}

				std::uint64_t data_begin = 0;
				if (m_write_cursor <= std::numeric_limits<std::uint64_t>::max() - (alignment - 1))
					data_begin = (m_write_cursor + alignment - 1) & ~static_cast<std::uint64_t>(alignment - 1);
				else
					return fail(out_error, error_code::resource_creation_failed, "Upload ring cursor overflow");

				const std::size_t physical_offset = static_cast<std::size_t>(data_begin % m_capacity);
				if (physical_offset > m_capacity - size)
				{
					data_begin += m_capacity - physical_offset;
				}

				if (data_begin <= std::numeric_limits<std::uint64_t>::max() - size)
				{
					const std::uint64_t span_end = data_begin + size;
					if (span_end - m_reclaim_cursor <= m_capacity)
					{
						const std::uint64_t reservation = m_next_reservation++;
						m_records.push_back({reservation, owner, m_write_cursor, span_end, range_state::open, 0});
						m_write_cursor = span_end;

						const std::size_t used = static_cast<std::size_t>(m_write_cursor - m_reclaim_cursor);
						m_peak_bytes_in_use = std::max(m_peak_bytes_in_use, used);
						m_allocations++;
						m_bytes += size;

						const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
							steady_clock::now() - wait_started);
						if (waited)
						{
							m_wait_count++;
							m_wait_time_ns += static_cast<std::uint64_t>(elapsed.count());
						}

						out.slice.buffer = m_buffer.get();
						out.slice.cpu_address = m_contents + (data_begin % m_capacity);
						out.slice.offset = static_cast<std::size_t>(data_begin % m_capacity);
						out.slice.size = size;
						out.slice.reservation_id = reservation;
						out.waited = waited;
						out.wait_time_ns = static_cast<std::uint64_t>(elapsed.count());
						return true;
					}
				}

				waited = true;
				if (!wait_forever && timeout <= std::chrono::milliseconds::zero())
				{
					m_timeout_count++;
					return fail(out_error, error_code::upload_ring_exhausted, "Metal upload ring has no reclaimable range");
				}

				if (wait_forever)
				{
					m_condition.wait(lock);
				}
				else if (m_condition.wait_until(lock, deadline) == std::cv_status::timeout)
				{
					m_timeout_count++;
					return fail(out_error, error_code::timed_out, "Timed out waiting for a Metal upload range");
				}
			}
		}

		void mark_committed(std::uint64_t owner, std::uint64_t fence) noexcept
		{
			std::lock_guard lock(m_mutex);
			for (range_record& record : m_records)
			{
				if (record.owner == owner && record.state == range_state::open)
				{
					record.state = range_state::committed;
					record.fence = fence;
				}
			}
		}

		void complete(std::uint64_t owner, std::uint64_t fence) noexcept
		{
			{
				std::lock_guard lock(m_mutex);
				for (range_record& record : m_records)
				{
					if (record.owner == owner && record.state == range_state::committed && record.fence == fence)
						record.state = range_state::completed;
				}
				reclaim_locked();
			}
			m_condition.notify_all();
		}

		void cancel(std::uint64_t owner) noexcept
		{
			{
				std::lock_guard lock(m_mutex);
				for (range_record& record : m_records)
				{
					if (record.owner == owner && record.state != range_state::completed)
						record.state = range_state::cancelled;
				}
				reclaim_locked();
			}
			m_condition.notify_all();
		}

		void request_stop() noexcept
		{
			{
				std::lock_guard lock(m_mutex);
				m_stopping = true;
			}
			m_condition.notify_all();
		}

		snapshot get_snapshot() const noexcept
		{
			std::lock_guard lock(m_mutex);
			return {
				.capacity = m_capacity,
				.bytes_in_use = static_cast<std::size_t>(m_write_cursor - m_reclaim_cursor),
				.peak_bytes_in_use = m_peak_bytes_in_use,
				.allocations = m_allocations,
				.bytes = m_bytes,
				.wait_count = m_wait_count,
				.wait_time_ns = m_wait_time_ns,
				.timeout_count = m_timeout_count,
			};
		}

	private:
		enum class range_state : std::uint8_t
		{
			open,
			committed,
			completed,
			cancelled,
		};

		struct range_record
		{
			std::uint64_t reservation = 0;
			std::uint64_t owner = 0;
			std::uint64_t span_begin = 0;
			std::uint64_t span_end = 0;
			range_state state = range_state::open;
			std::uint64_t fence = 0;
		};

		void reclaim_locked() noexcept
		{
			while (!m_records.empty())
			{
				const range_state state = m_records.front().state;
				if (state != range_state::completed && state != range_state::cancelled)
					break;
				m_reclaim_cursor = m_records.front().span_end;
				m_records.pop_front();
			}
		}

		objc_ref m_buffer;
		std::byte* m_contents = nullptr;
		const std::size_t m_capacity = 0;
		mutable std::mutex m_mutex;
		std::condition_variable m_condition;
		std::deque<range_record> m_records;
		std::uint64_t m_write_cursor = 0;
		std::uint64_t m_reclaim_cursor = 0;
		std::uint64_t m_next_reservation = 1;
		std::size_t m_peak_bytes_in_use = 0;
		std::uint64_t m_allocations = 0;
		std::uint64_t m_bytes = 0;
		std::uint64_t m_wait_count = 0;
		std::uint64_t m_wait_time_ns = 0;
		std::uint64_t m_timeout_count = 0;
		bool m_stopping = false;
	};

	class runtime_state final : public std::enable_shared_from_this<runtime_state>
	{
	public:
		runtime_state(
			objc_ref layer,
			objc_ref device,
			objc_ref queue,
			std::shared_ptr<upload_ring> uploads,
			runtime_config config) noexcept
			: m_layer(std::move(layer))
			, m_device(std::move(device))
			, m_queue(std::move(queue))
			, m_uploads(std::move(uploads))
			, m_config(config)
		{
		}

		~runtime_state()
		{
			request_stop();
			release_resources();
		}

		bool reserve_slot(
			std::chrono::milliseconds timeout,
			std::uint64_t& owner,
			error* out_error)
		{
			std::unique_lock lock(m_mutex);
			const bool wait_forever = timeout == std::chrono::milliseconds::max();
			const auto deadline = wait_forever ? steady_clock::time_point::max() : steady_clock::now() + timeout;

			while (!m_stopping && m_active_command_buffers >= m_config.max_command_buffers_in_flight)
			{
				if (wait_forever)
					m_condition.wait(lock);
				else if (timeout <= std::chrono::milliseconds::zero() ||
					m_condition.wait_until(lock, deadline) == std::cv_status::timeout)
					return fail(out_error, error_code::timed_out, "Timed out waiting for an in-flight Metal command-buffer slot");
			}

			if (m_stopping)
				return fail(out_error, error_code::stopping, "Metal runtime is stopping");

			owner = m_next_owner++;
			m_active_command_buffers++;
			m_peak_active_command_buffers = std::max(m_peak_active_command_buffers, m_active_command_buffers);
			m_command_buffers_started++;
			return true;
		}

		void abandon(std::uint64_t owner) noexcept
		{
			m_uploads->cancel(owner);
			{
				std::lock_guard lock(m_mutex);
				m_command_buffers_abandoned++;
				if (m_active_command_buffers)
					m_active_command_buffers--;
			}
			m_condition.notify_all();
		}

		bool prepare_commit(std::uint64_t& fence, error* out_error)
		{
			std::lock_guard lock(m_mutex);
			if (m_stopping)
				return fail(out_error, error_code::stopping, "Metal runtime stopped before command-buffer commit");
			fence = m_next_fence++;
			m_command_buffers_submitted++;
			return true;
		}

		void fail_before_submit(std::uint64_t owner, std::uint64_t fence, std::string message) noexcept
		{
			m_uploads->cancel(owner);
			command_completion completion;
			completion.fence_value = fence;
			completion.status = command_status::failed;
			completion.cpu_complete_time_ns = monotonic_time_ns();
			completion.metal_error_message = std::move(message);
			finish_completion(std::move(completion), true);
		}

		void complete(
			std::uint64_t owner,
			std::uint64_t fence,
			std::uint64_t submit_time,
			id<MTLCommandBuffer> command_buffer) noexcept
		{
			m_uploads->complete(owner, fence);

			command_completion completion;
			completion.fence_value = fence;
			completion.cpu_submit_time_ns = submit_time;
			completion.cpu_complete_time_ns = monotonic_time_ns();
			completion.status = command_buffer.status == MTLCommandBufferStatusCompleted
				? command_status::completed
				: command_status::failed;

			const double gpu_start = command_buffer.GPUStartTime;
			const double gpu_end = command_buffer.GPUEndTime;
			completion.gpu_start_time_ns = seconds_to_ns(gpu_start);
			completion.gpu_end_time_ns = seconds_to_ns(gpu_end);
			if (gpu_end >= gpu_start)
				completion.gpu_duration_ns = seconds_to_ns(gpu_end - gpu_start);

			if (NSError* metal_error = command_buffer.error)
			{
				completion.metal_error_code = metal_error.code;
				completion.metal_error_domain = utf8_string(metal_error.domain);
				completion.metal_error_message = utf8_string(metal_error.localizedDescription);
			}

			finish_completion(std::move(completion), command_buffer.status != MTLCommandBufferStatusCompleted);
		}

		void record_drawable(bool acquired) noexcept
		{
			std::lock_guard lock(m_mutex);
			if (acquired)
				m_drawable_acquisitions++;
			else
				m_drawable_misses++;
		}

		void request_stop() noexcept
		{
			{
				std::lock_guard lock(m_mutex);
				m_stopping = true;
			}
			m_uploads->request_stop();
			m_condition.notify_all();
		}

		bool wait_until_drained(std::chrono::milliseconds timeout) noexcept
		{
			std::unique_lock lock(m_mutex);
			if (timeout == std::chrono::milliseconds::max())
			{
				m_condition.wait(lock, [this] { return m_active_command_buffers == 0; });
				return true;
			}
			return m_condition.wait_for(lock, timeout, [this] { return m_active_command_buffers == 0; });
		}

		bool wait_for_fence(std::uint64_t fence, std::chrono::milliseconds timeout) noexcept
		{
			std::unique_lock lock(m_mutex);
			if (!fence || fence >= m_next_fence)
				return false;
			if (timeout == std::chrono::milliseconds::max())
			{
				m_condition.wait(lock, [this, fence] { return m_last_completed_fence >= fence; });
				return true;
			}
			return m_condition.wait_for(lock, timeout, [this, fence] { return m_last_completed_fence >= fence; });
		}

		bool poll_completion(command_completion& out)
		{
			std::lock_guard lock(m_mutex);
			if (m_completions.empty())
				return false;
			out = std::move(m_completions.front());
			m_completions.pop_front();
			return true;
		}

		telemetry_snapshot telemetry() const noexcept
		{
			telemetry_snapshot result;
			{
				std::lock_guard lock(m_mutex);
				result.command_buffers_started = m_command_buffers_started;
				result.command_buffers_submitted = m_command_buffers_submitted;
				result.command_buffers_completed = m_command_buffers_completed;
				result.command_buffers_failed = m_command_buffers_failed;
				result.command_buffers_abandoned = m_command_buffers_abandoned;
				result.drawable_acquisitions = m_drawable_acquisitions;
				result.drawable_misses = m_drawable_misses;
				result.accumulated_gpu_time_ns = m_accumulated_gpu_time_ns;
				result.last_completed_fence = m_last_completed_fence;
				result.active_command_buffers = m_active_command_buffers;
				result.peak_active_command_buffers = m_peak_active_command_buffers;
				result.stopping = m_stopping;
			}

			const upload_ring::snapshot uploads = m_uploads->get_snapshot();
			result.upload_ring_capacity = uploads.capacity;
			result.upload_ring_bytes_in_use = uploads.bytes_in_use;
			result.upload_ring_peak_bytes_in_use = uploads.peak_bytes_in_use;
			result.upload_allocations = uploads.allocations;
			result.upload_bytes = uploads.bytes;
			result.upload_wait_count = uploads.wait_count;
			result.upload_wait_time_ns = uploads.wait_time_ns;
			result.upload_timeout_count = uploads.timeout_count;
			return result;
		}

		objc_ref layer() const noexcept
		{
			std::lock_guard lock(m_mutex);
			return m_layer;
		}

		objc_ref device() const noexcept
		{
			std::lock_guard lock(m_mutex);
			return m_device;
		}

		objc_ref queue() const noexcept
		{
			std::lock_guard lock(m_mutex);
			return m_queue;
		}

		std::shared_ptr<upload_ring> uploads() const noexcept
		{
			return m_uploads;
		}

		bool stopping() const noexcept
		{
			std::lock_guard lock(m_mutex);
			return m_stopping;
		}

		void release_resources() noexcept
		{
			std::lock_guard lock(m_mutex);
			if (m_active_command_buffers != 0)
				return;
			m_layer.clear();
			m_queue.clear();
			m_device.clear();
		}

	private:
		void finish_completion(command_completion completion, bool failed) noexcept
		{
			{
				std::lock_guard lock(m_mutex);
				if (failed)
					m_command_buffers_failed++;
				else
					m_command_buffers_completed++;

				// A single persistent queue should complete in submission order, but
				// retaining the sparse set keeps fence waits correct even if a driver
				// reports callbacks out of order.
				m_finished_fences.insert(completion.fence_value);
				while (m_finished_fences.erase(m_last_completed_fence + 1))
					m_last_completed_fence++;

				const std::uint64_t non_overlapping_start = std::max(m_last_gpu_end_ns, completion.gpu_start_time_ns);
				if (completion.gpu_end_time_ns > non_overlapping_start)
				{
					m_accumulated_gpu_time_ns += completion.gpu_end_time_ns - non_overlapping_start;
					m_last_gpu_end_ns = completion.gpu_end_time_ns;
				}

				if (m_config.completion_history_limit)
				{
					while (m_completions.size() >= m_config.completion_history_limit)
						m_completions.pop_front();
					m_completions.push_back(std::move(completion));
				}

				if (m_active_command_buffers)
					m_active_command_buffers--;
			}
			m_condition.notify_all();
		}

		mutable std::mutex m_mutex;
		std::condition_variable m_condition;
		objc_ref m_layer;
		objc_ref m_device;
		objc_ref m_queue;
		std::shared_ptr<upload_ring> m_uploads;
		runtime_config m_config;
		std::deque<command_completion> m_completions;
		std::unordered_set<std::uint64_t> m_finished_fences;
		std::uint64_t m_next_owner = 1;
		std::uint64_t m_next_fence = 1;
		std::uint64_t m_last_completed_fence = 0;
		std::uint64_t m_last_gpu_end_ns = 0;
		std::uint64_t m_accumulated_gpu_time_ns = 0;
		std::uint64_t m_command_buffers_started = 0;
		std::uint64_t m_command_buffers_submitted = 0;
		std::uint64_t m_command_buffers_completed = 0;
		std::uint64_t m_command_buffers_failed = 0;
		std::uint64_t m_command_buffers_abandoned = 0;
		std::uint64_t m_drawable_acquisitions = 0;
		std::uint64_t m_drawable_misses = 0;
		std::uint32_t m_active_command_buffers = 0;
		std::uint32_t m_peak_active_command_buffers = 0;
		bool m_stopping = false;
	};
}

struct command_context::impl final
{
	std::shared_ptr<runtime_state> state;
	objc_ref command_buffer;
	std::shared_ptr<objc_ref> presented_drawable;
	std::uint64_t owner = 0;
	bool active = true;
	bool drawable_acquired = false;
	bool drawable_presented = false;

	~impl()
	{
		if (active && state)
			state->abandon(owner);
	}
};

struct drawable::impl final
{
	std::shared_ptr<runtime_state> state;
	objc_ref metal_drawable;
	void* texture = nullptr;
	std::uint64_t owner = 0;
	std::uint32_t width = 0;
	std::uint32_t height = 0;
};

struct runtime::impl final
{
	mutable std::mutex mutex;
	std::shared_ptr<runtime_state> state;
};

command_context::command_context() noexcept = default;
command_context::~command_context() = default;
command_context::command_context(command_context&&) noexcept = default;
command_context& command_context::operator=(command_context&&) noexcept = default;

command_context::operator bool() const noexcept
{
	return m_impl && m_impl->active && m_impl->command_buffer;
}

native_handle command_context::native_command_buffer() const noexcept
{
	return m_impl && m_impl->active ? m_impl->command_buffer.get() : nullptr;
}

std::uint64_t command_context::owner_id() const noexcept
{
	return m_impl && m_impl->active ? m_impl->owner : 0;
}

drawable::drawable() noexcept = default;
drawable::~drawable() = default;
drawable::drawable(drawable&&) noexcept = default;
drawable& drawable::operator=(drawable&&) noexcept = default;

drawable::operator bool() const noexcept
{
	return m_impl && m_impl->metal_drawable;
}

native_handle drawable::native_drawable() const noexcept
{
	return m_impl ? m_impl->metal_drawable.get() : nullptr;
}

native_handle drawable::texture() const noexcept
{
	return m_impl ? m_impl->texture : nullptr;
}

std::uint32_t drawable::width() const noexcept
{
	return m_impl ? m_impl->width : 0;
}

std::uint32_t drawable::height() const noexcept
{
	return m_impl ? m_impl->height : 0;
}

runtime::runtime()
	: m_impl(std::make_unique<impl>())
{
}

runtime::~runtime()
{
	stop();
}

runtime::runtime(runtime&& other) noexcept
	: m_impl(std::move(other.m_impl))
{
}

runtime& runtime::operator=(runtime&& other) noexcept
{
	if (this != &other)
	{
		stop();
		m_impl = std::move(other.m_impl);
	}
	return *this;
}

bool runtime::start(native_handle metal_layer, const runtime_config& config, error* out_error)
{
	clear_error(out_error);
	if (!m_impl)
		m_impl = std::make_unique<impl>();
	if (!metal_layer)
		return fail(out_error, error_code::invalid_argument, "A CAMetalLayer is required");
	if (!config.max_command_buffers_in_flight || config.max_command_buffers_in_flight > maximum_in_flight_limit)
		return fail(out_error, error_code::invalid_argument, "In-flight command-buffer count must be between 1 and 8");
	if (config.completion_history_limit > maximum_completion_history)
		return fail(out_error, error_code::invalid_argument, "Completion history cannot exceed 1024 records");

	std::size_t ring_size = 0;
	if (!round_up(std::max(config.upload_ring_bytes, ring_granularity), ring_granularity, ring_size))
		return fail(out_error, error_code::invalid_argument, "Upload ring size cannot be represented");

	{
		std::lock_guard lock(m_impl->mutex);
		if (m_impl->state)
			return fail(out_error, error_code::already_running, "Metal runtime is already active");
	}

	@autoreleasepool
	{
		@try
		{
			CAMetalLayer* layer = (__bridge CAMetalLayer*)metal_layer;
			if (![layer isKindOfClass:CAMetalLayer.class])
				return fail(out_error, error_code::invalid_argument, "Native display handle is not a CAMetalLayer");

			id<MTLDevice> device = layer.device;
			if (!device)
				return fail(out_error, error_code::invalid_argument, "CAMetalLayer must have a persistent MTLDevice before runtime start");
			if (!device.hasUnifiedMemory)
				return fail(out_error, error_code::unsupported_device, "Direct iOS RSX runtime requires unified Metal memory");
			if (ring_size > device.maxBufferLength)
				return fail(out_error, error_code::invalid_argument, "Upload ring exceeds the Metal device's maximum buffer length");

			id<MTLCommandQueue> queue = [device newCommandQueueWithMaxCommandBufferCount:config.max_command_buffers_in_flight];
			if (!queue)
				return fail(out_error, error_code::resource_creation_failed, "Failed to create the persistent Metal command queue");
			queue.label = @"ARMSX3 RSX Metal Queue";
			objc_ref queue_ref(queue);
			release_created_object(queue);

			constexpr MTLResourceOptions upload_options =
				MTLResourceStorageModeShared |
				MTLResourceCPUCacheModeWriteCombined |
				MTLResourceHazardTrackingModeTracked;
			id<MTLBuffer> buffer = [device newBufferWithLength:ring_size options:upload_options];
			if (!buffer)
				return fail(out_error, error_code::resource_creation_failed, "Failed to create the fixed Metal upload ring");
			buffer.label = @"ARMSX3 RSX Metal Upload Ring";
			objc_ref buffer_ref(buffer);
			release_created_object(buffer);

			std::byte* contents = static_cast<std::byte*>(buffer.contents);
			if (!contents)
				return fail(out_error, error_code::resource_creation_failed, "Shared Metal upload ring has no CPU mapping");

			auto uploads = std::make_shared<upload_ring>(std::move(buffer_ref), contents, ring_size);
			auto state = std::make_shared<runtime_state>(
				objc_ref(layer), objc_ref(device), std::move(queue_ref), std::move(uploads), config);

			std::lock_guard lock(m_impl->mutex);
			if (m_impl->state)
				return fail(out_error, error_code::already_running, "Metal runtime was started concurrently");
			m_impl->state = std::move(state);
			return true;
		}
		@catch (NSException* exception)
		{
			return fail(out_error, error_code::metal_exception,
				"Objective-C exception while starting Metal runtime: " + utf8_string(exception.reason));
		}
	}
}

stop_result runtime::stop(std::chrono::milliseconds timeout) noexcept
{
	if (!m_impl)
		return stop_result::not_running;

	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = std::exchange(m_impl->state, {});
	}
	if (!state)
		return stop_result::not_running;

	state->request_stop();
	const bool drained = state->wait_until_drained(std::max(timeout, std::chrono::milliseconds::zero()));
	if (drained)
		state->release_resources();
	return drained ? stop_result::drained : stop_result::deferred;
}

bool runtime::running() const noexcept
{
	if (!m_impl)
		return false;
	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	return state && !state->stopping();
}

native_handle runtime::device() const noexcept
{
	if (!m_impl)
		return nullptr;
	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	return state ? state->device().get() : nullptr;
}

native_handle runtime::command_queue() const noexcept
{
	if (!m_impl)
		return nullptr;
	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	return state ? state->queue().get() : nullptr;
}

bool runtime::begin_command_buffer(
	command_context& out_context,
	std::string_view label,
	std::chrono::milliseconds timeout,
	error* out_error)
{
	clear_error(out_error);
	if (out_context)
		return fail(out_error, error_code::invalid_argument, "Output command context is already active");
	if (!m_impl)
		return fail(out_error, error_code::not_running, "Metal runtime is not active");

	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	if (!state)
		return fail(out_error, error_code::not_running, "Metal runtime is not active");

	std::uint64_t owner = 0;
	if (!state->reserve_slot(std::max(timeout, std::chrono::milliseconds::zero()), owner, out_error))
		return false;

	@autoreleasepool
	{
		@try
		{
			id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)state->queue().get();
			id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
			if (!command_buffer)
			{
				state->abandon(owner);
				return fail(out_error, error_code::command_buffer_unavailable, "Metal command queue returned no command buffer");
			}

			if (!label.empty())
			{
				NSString* native_label = [[NSString alloc]
					initWithBytes:label.data() length:label.size() encoding:NSUTF8StringEncoding];
				if (native_label)
					command_buffer.label = native_label;
				release_created_object(native_label);
			}

			auto context = std::make_unique<command_context::impl>();
			context->state = std::move(state);
			context->command_buffer.reset(command_buffer);
			context->owner = owner;
			out_context.m_impl = std::move(context);
			return true;
		}
		@catch (NSException* exception)
		{
			state->abandon(owner);
			return fail(out_error, error_code::metal_exception,
				"Objective-C exception while creating command buffer: " + utf8_string(exception.reason));
		}
	}
}

bool runtime::acquire_drawable(command_context& context, drawable& out_drawable, error* out_error)
{
	clear_error(out_error);
	if (out_drawable)
		return fail(out_error, error_code::invalid_argument, "Output drawable is already active");
	if (!context.m_impl || !context.m_impl->active)
		return fail(out_error, error_code::invalid_argument, "An active command context is required");
	if (context.m_impl->drawable_acquired)
		return fail(out_error, error_code::invalid_argument, "Command context already acquired a drawable");

	std::shared_ptr<runtime_state> state;
	{
		if (!m_impl)
			return fail(out_error, error_code::not_running, "Metal runtime is not active");
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	if (!state || state != context.m_impl->state || state->stopping())
		return fail(out_error, error_code::stopping, "Command context does not belong to the active Metal runtime");

	@autoreleasepool
	{
		@try
		{
			objc_ref layer_ref = state->layer();
			CAMetalLayer* layer = (__bridge CAMetalLayer*)layer_ref.get();
			id<CAMetalDrawable> metal_drawable = [layer nextDrawable];
			if (!metal_drawable)
			{
				state->record_drawable(false);
				return fail(out_error, error_code::drawable_unavailable, "CAMetalLayer returned no drawable");
			}

			id<MTLTexture> texture = metal_drawable.texture;
			auto frame = std::make_unique<drawable::impl>();
			frame->state = state;
			frame->metal_drawable.reset(metal_drawable);
			frame->texture = (__bridge void*)texture;
			frame->owner = context.m_impl->owner;
			frame->width = static_cast<std::uint32_t>(std::min<NSUInteger>(texture.width, UINT32_MAX));
			frame->height = static_cast<std::uint32_t>(std::min<NSUInteger>(texture.height, UINT32_MAX));
			context.m_impl->drawable_acquired = true;
			out_drawable.m_impl = std::move(frame);
			state->record_drawable(true);
			return true;
		}
		@catch (NSException* exception)
		{
			state->record_drawable(false);
			return fail(out_error, error_code::metal_exception,
				"Objective-C exception while acquiring drawable: " + utf8_string(exception.reason));
		}
	}
}

bool runtime::allocate_upload(
	command_context& context,
	std::size_t size,
	std::size_t alignment,
	std::chrono::milliseconds timeout,
	upload_slice& out_slice,
	error* out_error)
{
	clear_error(out_error);
	out_slice = {};
	if (!context.m_impl || !context.m_impl->active)
		return fail(out_error, error_code::invalid_argument, "An active command context is required");

	std::shared_ptr<runtime_state> state;
	{
		if (!m_impl)
			return fail(out_error, error_code::not_running, "Metal runtime is not active");
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	if (!state || state != context.m_impl->state || state->stopping())
		return fail(out_error, error_code::stopping, "Command context does not belong to the active Metal runtime");

	upload_ring::allocation allocation;
	if (!state->uploads()->allocate(
		context.m_impl->owner,
		size,
		alignment,
		std::max(timeout, std::chrono::milliseconds::zero()),
		allocation,
		out_error))
	{
		return false;
	}
	out_slice = allocation.slice;
	return true;
}

bool runtime::present(command_context& context, drawable&& frame, error* out_error)
{
	clear_error(out_error);
	if (!context.m_impl || !context.m_impl->active)
		return fail(out_error, error_code::invalid_argument, "An active command context is required");
	if (!frame.m_impl || !frame.m_impl->metal_drawable)
		return fail(out_error, error_code::invalid_argument, "An active drawable is required");
	if (context.m_impl->drawable_presented)
		return fail(out_error, error_code::invalid_argument, "Command context already has a presented drawable");
	if (frame.m_impl->state != context.m_impl->state || frame.m_impl->owner != context.m_impl->owner)
		return fail(out_error, error_code::invalid_argument, "Drawable belongs to a different command context");

	@autoreleasepool
	{
		@try
		{
			id<MTLCommandBuffer> command_buffer = (__bridge id<MTLCommandBuffer>)context.m_impl->command_buffer.get();
			id<CAMetalDrawable> metal_drawable = (__bridge id<CAMetalDrawable>)frame.m_impl->metal_drawable.get();
			[command_buffer presentDrawable:metal_drawable];

			context.m_impl->presented_drawable =
				std::make_shared<objc_ref>(std::move(frame.m_impl->metal_drawable));
			context.m_impl->drawable_presented = true;
			frame.m_impl.reset();
			return true;
		}
		@catch (NSException* exception)
		{
			return fail(out_error, error_code::metal_exception,
				"Objective-C exception while scheduling drawable presentation: " + utf8_string(exception.reason));
		}
	}
}

bool runtime::commit(command_context&& context, std::uint64_t& fence_value, error* out_error)
{
	clear_error(out_error);
	fence_value = 0;
	if (!context.m_impl || !context.m_impl->active)
		return fail(out_error, error_code::invalid_argument, "An active command context is required");

	std::shared_ptr<runtime_state> state;
	{
		if (!m_impl)
			return fail(out_error, error_code::not_running, "Metal runtime is not active");
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	if (!state || state != context.m_impl->state)
		return fail(out_error, error_code::stopping, "Command context does not belong to the active Metal runtime");

	std::uint64_t fence = 0;
	if (!state->prepare_commit(fence, out_error))
		return false;
	state->uploads()->mark_committed(context.m_impl->owner, fence);

	const std::uint64_t owner = context.m_impl->owner;
	const std::uint64_t submit_time = monotonic_time_ns();
	std::shared_ptr<objc_ref> drawable_lifetime = context.m_impl->presented_drawable;
	id<MTLCommandBuffer> command_buffer = (__bridge id<MTLCommandBuffer>)context.m_impl->command_buffer.get();

	@autoreleasepool
	{
		@try
		{
			[command_buffer addCompletedHandler:^(id<MTLCommandBuffer> completed_buffer)
			{
				@autoreleasepool
				{
					// Keeping this captured object alive explicitly retains the drawable
					// through GPU completion, independent of driver implementation detail.
					(void)drawable_lifetime;
					state->complete(owner, fence, submit_time, completed_buffer);
				}
			}];

			context.m_impl->active = false;
			[command_buffer commit];
			fence_value = fence;
			context.m_impl.reset();
			return true;
		}
		@catch (NSException* exception)
		{
			context.m_impl->active = false;
			state->fail_before_submit(owner, fence,
				"Objective-C exception while committing command buffer: " + utf8_string(exception.reason));
			context.m_impl.reset();
			return fail(out_error, error_code::metal_exception,
				"Objective-C exception while committing Metal command buffer: " + utf8_string(exception.reason));
		}
	}
}

void runtime::abandon(command_context&& context) noexcept
{
	context.m_impl.reset();
}

bool runtime::wait_for_fence(std::uint64_t fence_value, std::chrono::milliseconds timeout) const noexcept
{
	if (!m_impl)
		return false;
	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	return state && state->wait_for_fence(fence_value, std::max(timeout, std::chrono::milliseconds::zero()));
}

bool runtime::poll_completion(command_completion& out_completion)
{
	if (!m_impl)
		return false;
	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	return state && state->poll_completion(out_completion);
}

telemetry_snapshot runtime::telemetry() const noexcept
{
	if (!m_impl)
		return {};
	std::shared_ptr<runtime_state> state;
	{
		std::lock_guard lock(m_impl->mutex);
		state = m_impl->state;
	}
	return state ? state->telemetry() : telemetry_snapshot{};
}
}
