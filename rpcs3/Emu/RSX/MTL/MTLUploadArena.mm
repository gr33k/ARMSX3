#include "MTLUploadArena.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cstddef>
#include <limits>
#include <mutex>
#include <optional>
#include <utility>
#include <vector>

namespace
{
	using metal_device_ref = id<MTLDevice>;
	using metal_buffer_ref = id<MTLBuffer>;
	using metal_command_buffer_ref = id<MTLCommandBuffer>;

	bool is_power_of_two(std::size_t value) noexcept
	{
		return value && !(value & (value - 1));
	}

	bool align_up(std::size_t value, std::size_t alignment, std::size_t& result) noexcept
	{
		if (!is_power_of_two(alignment) || value > std::numeric_limits<std::size_t>::max() - (alignment - 1))
		{
			return false;
		}

		result = (value + alignment - 1) & ~(alignment - 1);
		return true;
	}

	bool round_up(std::size_t value, std::size_t granularity, std::size_t& result) noexcept
	{
		if (!granularity || value > std::numeric_limits<std::size_t>::max() - (granularity - 1))
		{
			return false;
		}

		result = ((value + granularity - 1) / granularity) * granularity;
		return true;
	}

	std::string objc_string(NSString* value, const char* fallback)
	{
		if (const char* text = value.UTF8String)
		{
			return text;
		}

		return fallback;
	}
} // namespace

namespace mtl
{
	struct upload_arena::state
	{
		enum class page_status : std::uint8_t
		{
			free,
			active,
			pending_completion,
		};

		struct page
		{
			__strong metal_buffer_ref buffer = nil;
			std::byte* contents = nullptr;
			std::size_t capacity = 0;
			std::size_t cursor = 0;
			std::size_t used = 0;
			std::uint64_t frame_index = 0;
			page_status status = page_status::free;
		};

		explicit state(void* metal_device, upload_arena_limits requested_limits)
			: limits(requested_limits)
		{
			@autoreleasepool
			{
				@try
				{
					if (!metal_device)
					{
						init_error = "Metal upload arena received a null device";
						return;
					}

					id candidate = (__bridge id)metal_device;
					if (![candidate conformsToProtocol:@protocol(MTLDevice)])
					{
						init_error = "Metal upload arena object does not conform to MTLDevice";
						return;
					}
					device = candidate;

					if (!limits.page_bytes || !limits.max_total_bytes || !limits.max_allocation_bytes ||
						!is_power_of_two(limits.max_alignment))
					{
						init_error = "Metal upload arena limits are invalid";
						return;
					}
					if (limits.page_bytes > limits.max_allocation_bytes ||
						limits.max_allocation_bytes > limits.max_total_bytes)
					{
						init_error = "Metal upload arena page/allocation/total limits are inconsistent";
						return;
					}
					if (limits.max_alignment > limits.page_bytes)
					{
						init_error = "Metal upload alignment exceeds the page size";
						return;
					}
					if (limits.max_allocation_bytes > device.maxBufferLength)
					{
						init_error = "Metal upload allocation limit exceeds MTLDevice.maxBufferLength";
						return;
					}
				}
				@catch (NSException* exception)
				{
					init_error = objc_string(exception.reason, "Objective-C exception initializing Metal uploads");
				}
			}
		}

		void release_page(page& value) noexcept
		{
			retained_bytes -= value.capacity;
			value.buffer = nil;
			value.contents = nullptr;
			value.capacity = 0;
			value.cursor = 0;
			value.used = 0;
			value.frame_index = 0;
			value.status = page_status::free;
		}

		void make_free(page& value) noexcept
		{
			value.cursor = 0;
			value.used = 0;
			value.frame_index = 0;
			value.status = page_status::free;
		}

		void retire(std::uint64_t frame_index) noexcept
		{
			std::lock_guard lock(mutex);
			for (auto iterator = pages.begin(); iterator != pages.end();)
			{
				page& value = **iterator;
				if (value.status != page_status::pending_completion || value.frame_index != frame_index)
				{
					++iterator;
					continue;
				}

				if (stopped)
				{
					release_page(value);
					iterator = pages.erase(iterator);
				}
				else
				{
					make_free(value);
					++iterator;
				}
			}
		}

		void cancel(std::uint64_t frame_index) noexcept
		{
			std::lock_guard lock(mutex);
			if (active_frame == frame_index)
			{
				active_frame.reset();
			}

			for (auto iterator = pages.begin(); iterator != pages.end();)
			{
				page& value = **iterator;
				if (value.frame_index != frame_index || value.status == page_status::free)
				{
					++iterator;
					continue;
				}

				if (stopped)
				{
					release_page(value);
					iterator = pages.erase(iterator);
				}
				else
				{
					make_free(value);
					++iterator;
				}
			}
		}

		mutable std::mutex mutex;
		__strong metal_device_ref device = nil;
		upload_arena_limits limits{};
		std::vector<std::unique_ptr<page>> pages;
		std::optional<std::uint64_t> active_frame;
		std::string init_error;
		std::size_t retained_bytes = 0;
		std::size_t peak_retained_bytes = 0;
		std::uint64_t allocations = 0;
		std::uint64_t uploaded_bytes = 0;
		std::uint64_t exhaustion_failures = 0;
		bool stopped = false;
	};

	upload_arena::upload_arena(void* metal_device, upload_arena_limits limits)
		: m_state(std::make_shared<state>(metal_device, limits))
	{
	}

	upload_arena::~upload_arena()
	{
		shutdown();
	}

	upload_arena::upload_arena(upload_arena&& other) noexcept = default;

	upload_arena& upload_arena::operator=(upload_arena&& other) noexcept
	{
		if (this != &other)
		{
			shutdown();
			m_state = std::move(other.m_state);
		}
		return *this;
	}

	bool upload_arena::valid() const noexcept
	{
		const auto shared = m_state;
		if (!shared)
		{
			return false;
		}

		std::lock_guard lock(shared->mutex);
		return shared->device && shared->init_error.empty() && !shared->stopped;
	}

	std::string upload_arena::initialization_error() const
	{
		const auto shared = m_state;
		if (!shared)
		{
			return "Metal upload arena is not initialized";
		}

		std::lock_guard lock(shared->mutex);
		return shared->init_error;
	}

	bool upload_arena::begin_frame(std::uint64_t frame_index, std::string& error)
	{
		const auto shared = m_state;
		if (!shared)
		{
			error = "Metal upload arena is not initialized";
			return false;
		}

		std::lock_guard lock(shared->mutex);
		if (!shared->device || shared->stopped || !shared->init_error.empty())
		{
			error = shared->init_error.empty() ? "Metal upload arena is stopped" : shared->init_error;
			return false;
		}
		if (shared->active_frame)
		{
			error = "Metal upload arena already has an open frame";
			return false;
		}

		shared->active_frame = frame_index;
		return true;
	}

	bool upload_arena::allocate(
		std::uint64_t frame_index,
		std::size_t size,
		std::size_t alignment,
		upload_allocation& allocation,
		std::string& error)
	{
		allocation = {};
		const auto shared = m_state;
		if (!shared)
		{
			error = "Metal upload arena is not initialized";
			return false;
		}

		std::lock_guard lock(shared->mutex);
		if (!shared->active_frame || *shared->active_frame != frame_index)
		{
			error = "Metal upload allocation does not belong to the open frame";
			return false;
		}
		if (!size || size > shared->limits.max_allocation_bytes)
		{
			error = "Metal upload size is zero or exceeds the per-allocation limit";
			return false;
		}
		if (!is_power_of_two(alignment) || alignment > shared->limits.max_alignment)
		{
			error = "Metal upload alignment is invalid";
			return false;
		}

		state::page* selected = nullptr;
		std::size_t selected_offset = 0;
		for (const auto& candidate : shared->pages)
		{
			if (candidate->status != state::page_status::active || candidate->frame_index != frame_index)
			{
				continue;
			}

			std::size_t offset = 0;
			if (align_up(candidate->cursor, alignment, offset) &&
				offset <= candidate->capacity && size <= candidate->capacity - offset)
			{
				selected = candidate.get();
				selected_offset = offset;
				break;
			}
		}

		if (!selected)
		{
			for (const auto& candidate : shared->pages)
			{
				if (candidate->status == state::page_status::free && candidate->capacity >= size &&
					(!selected || candidate->capacity < selected->capacity))
				{
					selected = candidate.get();
				}
			}

			if (selected)
			{
				selected->status = state::page_status::active;
				selected->frame_index = frame_index;
				selected->cursor = 0;
				selected->used = 0;
				selected_offset = 0;
			}
		}

		if (!selected)
		{
			std::size_t capacity = 0;
			if (!round_up(std::max(size, shared->limits.page_bytes), shared->limits.page_bytes, capacity) ||
				capacity > shared->limits.max_allocation_bytes)
			{
				error = "Metal upload page capacity cannot be represented within configured limits";
				return false;
			}

			while (capacity > shared->limits.max_total_bytes - std::min(
				shared->retained_bytes, shared->limits.max_total_bytes))
			{
				auto largest_free = shared->pages.end();
				for (auto iterator = shared->pages.begin(); iterator != shared->pages.end(); ++iterator)
				{
					if ((*iterator)->status == state::page_status::free &&
						(largest_free == shared->pages.end() || (*iterator)->capacity > (*largest_free)->capacity))
					{
						largest_free = iterator;
					}
				}

				if (largest_free == shared->pages.end())
				{
					shared->exhaustion_failures++;
					error = "Metal upload arena exhausted its fixed 64 MiB budget";
					return false;
				}

				shared->release_page(**largest_free);
				shared->pages.erase(largest_free);
			}

			@try
			{
				constexpr MTLResourceOptions options =
					MTLResourceStorageModeShared |
					MTLResourceCPUCacheModeWriteCombined |
					MTLResourceHazardTrackingModeTracked;
				metal_buffer_ref buffer = [shared->device newBufferWithLength:capacity options:options];
				if (!buffer || !buffer.contents)
				{
					error = "Metal could not allocate a CPU-visible upload page";
					return false;
				}

				auto page = std::make_unique<state::page>();
				page->buffer = buffer;
				page->buffer.label = [NSString stringWithFormat:
					@"ARMSX3 native Metal upload page %zu", shared->pages.size()];
				page->contents = static_cast<std::byte*>(buffer.contents);
				page->capacity = capacity;
				page->frame_index = frame_index;
				page->status = state::page_status::active;
				selected = page.get();
				shared->pages.push_back(std::move(page));
				shared->retained_bytes += capacity;
				shared->peak_retained_bytes = std::max(shared->peak_retained_bytes, shared->retained_bytes);
			}
			@catch (NSException* exception)
			{
				error = objc_string(exception.reason, "Objective-C exception allocating Metal uploads");
				return false;
			}
		}

		selected->cursor = selected_offset + size;
		selected->used = std::max(selected->used, selected->cursor);
		shared->allocations++;
		shared->uploaded_bytes += size;
		allocation.cpu_address = selected->contents + selected_offset;
		allocation.native_buffer = (__bridge void*)selected->buffer;
		allocation.offset = selected_offset;
		allocation.size = size;
		return true;
	}

	bool upload_arena::finish_frame(
		std::uint64_t frame_index,
		void* command_buffer,
		std::string& error)
	{
		const auto shared = m_state;
		if (!shared)
		{
			error = "Metal upload arena is not initialized";
			return false;
		}

		metal_command_buffer_ref native_command_buffer = nil;
		@try
		{
			id candidate = (__bridge id)command_buffer;
			if (!candidate || ![candidate conformsToProtocol:@protocol(MTLCommandBuffer)])
			{
				error = "Metal upload finalization received an invalid command buffer";
				return false;
			}
			native_command_buffer = candidate;
		}
		@catch (NSException* exception)
		{
			error = objc_string(exception.reason, "Objective-C exception validating Metal uploads");
			return false;
		}

		bool has_uploads = false;
		{
			std::lock_guard lock(shared->mutex);
			if (!shared->active_frame || *shared->active_frame != frame_index)
			{
				error = "Metal upload finalization does not match the open frame";
				return false;
			}

			for (const auto& page : shared->pages)
			{
				if (page->status == state::page_status::active && page->frame_index == frame_index)
				{
					page->status = state::page_status::pending_completion;
					has_uploads = true;
				}
			}
			shared->active_frame.reset();
		}

		if (!has_uploads)
		{
			return true;
		}

		@try
		{
			const auto completion_state = shared;
			[native_command_buffer addCompletedHandler:^(metal_command_buffer_ref completed) {
				(void)completed;
				completion_state->retire(frame_index);
			}];
		}
		@catch (NSException* exception)
		{
			shared->cancel(frame_index);
			error = objc_string(exception.reason, "Objective-C exception scheduling Metal upload retirement");
			return false;
		}

		return true;
	}

	void upload_arena::abandon_frame(std::uint64_t frame_index) noexcept
	{
		if (const auto shared = m_state)
		{
			shared->cancel(frame_index);
		}
	}

	void upload_arena::shutdown() noexcept
	{
		auto shared = std::exchange(m_state, {});
		if (!shared)
		{
			return;
		}

		std::lock_guard lock(shared->mutex);
		shared->stopped = true;
		shared->active_frame.reset();
		for (auto iterator = shared->pages.begin(); iterator != shared->pages.end();)
		{
			if ((*iterator)->status == state::page_status::pending_completion)
			{
				++iterator;
				continue;
			}

			shared->release_page(**iterator);
			iterator = shared->pages.erase(iterator);
		}
		shared->device = nil;
	}

	upload_arena_stats upload_arena::stats() const noexcept
	{
		upload_arena_stats result;
		const auto shared = m_state;
		if (!shared)
		{
			return result;
		}

		std::lock_guard lock(shared->mutex);
		result.retained_bytes = shared->retained_bytes;
		result.peak_retained_bytes = shared->peak_retained_bytes;
		result.page_count = shared->pages.size();
		result.allocations = shared->allocations;
		result.uploaded_bytes = shared->uploaded_bytes;
		result.exhaustion_failures = shared->exhaustion_failures;
		for (const auto& page : shared->pages)
		{
			if (page->status == state::page_status::active)
			{
				result.active_bytes += page->used;
			}
			else if (page->status == state::page_status::pending_completion)
			{
				result.in_flight_bytes += page->used;
			}
		}
		return result;
	}
} // namespace mtl
