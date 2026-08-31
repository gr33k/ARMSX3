#pragma once

#include <util/types.hpp>
#include "Emu/RSX/Common/simple_array.hpp"

#include <vector>

namespace vk
{
	class data_heap;

	namespace data_heap_manager
	{
		struct managed_heap_snapshot_entry_t
		{
			vk::data_heap* heap = nullptr;
			usz get_pos = 0;
			u64 generation = 0;
		};

		struct managed_heap_snapshot_t
		{
			u64 id = 0;
			std::vector<managed_heap_snapshot_entry_t> heaps;

			void clear()
			{
				id = 0;
				heaps.clear();
			}
		};

		// Submit ring buffer for management
		void register_ring_buffer(vk::data_heap& heap);

		// Bulk registration
		void register_ring_buffers(std::initializer_list<std::reference_wrapper<vk::data_heap>> heaps);

		// Capture managed ring buffers at the current allocation positions.
		void capture_snapshot(managed_heap_snapshot_t& snapshot);

		// Synchronize heaps with a completed snapshot when it is still current.
		void restore_snapshot(const managed_heap_snapshot_t& snapshot);

		// Reset all managed heap allocations
		void reset_heap_allocations();

		// Cleanup
		void reset();

		// Retrieve as list
		rsx::simple_array<vk::data_heap*> to_list();
	}
}
