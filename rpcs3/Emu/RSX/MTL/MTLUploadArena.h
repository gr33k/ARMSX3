#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace mtl
{
	struct upload_arena_limits
	{
		std::size_t page_bytes = 4u * 1024u * 1024u;
		std::size_t max_total_bytes = 64u * 1024u * 1024u;
		std::size_t max_allocation_bytes = 16u * 1024u * 1024u;
		std::size_t max_alignment = 64u * 1024u;
	};

	struct upload_allocation
	{
		void* cpu_address = nullptr;
		// Borrowed id<MTLBuffer>. The arena retains it through completion or abandon.
		void* native_buffer = nullptr;
		std::size_t offset = 0;
		std::size_t size = 0;

		[[nodiscard]] explicit operator bool() const noexcept
		{
			return cpu_address && native_buffer && size;
		}
	};

	struct upload_arena_stats
	{
		std::size_t retained_bytes = 0;
		std::size_t active_bytes = 0;
		std::size_t in_flight_bytes = 0;
		std::size_t peak_retained_bytes = 0;
		std::size_t page_count = 0;
		std::uint64_t allocations = 0;
		std::uint64_t uploaded_bytes = 0;
		std::uint64_t exhaustion_failures = 0;
	};

	// One arena belongs to one MTLDevice and one serial guest-backend timeline.
	// It never waits for the GPU or grows beyond max_total_bytes.
	class upload_arena
	{
	public:
		explicit upload_arena(void* metal_device, upload_arena_limits limits = {});
		~upload_arena();

		upload_arena(const upload_arena&) = delete;
		upload_arena& operator=(const upload_arena&) = delete;
		upload_arena(upload_arena&&) noexcept;
		upload_arena& operator=(upload_arena&&) noexcept;

		[[nodiscard]] bool valid() const noexcept;
		[[nodiscard]] std::string initialization_error() const;
		[[nodiscard]] bool begin_frame(std::uint64_t frame_index, std::string& error);
		[[nodiscard]] bool allocate(
			std::uint64_t frame_index,
			std::size_t size,
			std::size_t alignment,
			upload_allocation& allocation,
			std::string& error);
		// command_buffer is an uncommitted id<MTLCommandBuffer>.
		[[nodiscard]] bool finish_frame(
			std::uint64_t frame_index,
			void* command_buffer,
			std::string& error);

		void abandon_frame(std::uint64_t frame_index) noexcept;
		void shutdown() noexcept;
		[[nodiscard]] upload_arena_stats stats() const noexcept;

	private:
		struct state;
		std::shared_ptr<state> m_state;
	};
} // namespace mtl
