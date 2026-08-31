#include "stdafx.h"
#include "VKDataHeapManager.h"

#include "vkutils/data_heap.h"
#include <mutex>
#include <unordered_set>

namespace vk::data_heap_manager
{
	std::unordered_set<vk::data_heap*> g_managed_heaps;
	std::mutex g_manager_mutex;
	u64 g_snapshot_counter = 0;
	u64 g_last_applied_snapshot = 0;

	rsx::simple_array<vk::data_heap*> to_list()
	{
		std::lock_guard lock(g_manager_mutex);
		rsx::simple_array<vk::data_heap*> result;
		result.resize(::size32(g_managed_heaps));
		std::copy(g_managed_heaps.begin(), g_managed_heaps.end(), result.begin());
		return result;
	}

	void register_ring_buffer(vk::data_heap& heap)
	{
		std::lock_guard lock(g_manager_mutex);
		g_managed_heaps.insert(&heap);
	}

	void register_ring_buffers(std::initializer_list<std::reference_wrapper<vk::data_heap>> heaps)
	{
		std::lock_guard lock(g_manager_mutex);
		for (auto&& heap : heaps)
		{
			g_managed_heaps.insert(&heap.get());
		}
	}

	void capture_snapshot(managed_heap_snapshot_t& snapshot)
	{
		std::lock_guard lock(g_manager_mutex);
		snapshot.id = ++g_snapshot_counter;
		snapshot.heaps.clear();
		snapshot.heaps.reserve(g_managed_heaps.size());

		for (auto& heap : g_managed_heaps)
		{
			snapshot.heaps.push_back({
				heap,
				heap->get_current_put_pos_minus_one(),
				heap->generation(),
			});
		}
	}

	void restore_snapshot(const managed_heap_snapshot_t& snapshot)
	{
		std::lock_guard lock(g_manager_mutex);
		if (!snapshot.id || snapshot.id <= g_last_applied_snapshot)
		{
			return;
		}

		for (const auto& entry : snapshot.heaps)
		{
			if (!g_managed_heaps.contains(entry.heap) ||
				entry.generation != entry.heap->generation())
			{
				continue;
			}

			entry.heap->set_get_pos(entry.get_pos);
			entry.heap->notify();
		}

		g_last_applied_snapshot = snapshot.id;
	}

	void reset_heap_allocations()
	{
		std::lock_guard lock(g_manager_mutex);
		for (auto& heap : g_managed_heaps)
		{
			heap->reset_allocation_stats();
		}
	}

	void reset()
	{
		std::lock_guard lock(g_manager_mutex);
		for (auto& heap : g_managed_heaps)
		{
			heap->destroy();
		}

		g_managed_heaps.clear();
		// Snapshot ids intentionally stay monotonic so late completions from a
		// destroyed renderer can never become current after reinitialization.
	}
}
