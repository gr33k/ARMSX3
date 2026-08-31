#include "rpcs3/ios/IOSMemoryPressurePolicy.h"

#include <cassert>

using rpcs3::ios::process_memory_mib;
using rpcs3::ios::process_memory_pressure;

int main()
{
	using rpcs3::ios::get_llvm_compile_thread_limit;
	using rpcs3::ios::get_bounded_reclaim_pressure;
	using rpcs3::ios::get_memory_reclaim_interval_ms;
	using rpcs3::ios::get_process_memory_pressure;
	using rpcs3::ios::get_process_pressure_texture_cache_quota;
	using rpcs3::ios::get_savestate_compression_thread_limit;
	using rpcs3::ios::get_soft_vram_memory_pressure;
	using rpcs3::ios::has_safe_savestate_headroom;
	using rpcs3::ios::should_rearm_destructive_reclaim;

	static_assert(get_llvm_compile_thread_limit(10, 0) == 3);
	static_assert(get_llvm_compile_thread_limit(2, 0) == 2);
	static_assert(get_llvm_compile_thread_limit(10, 6) == 6);
	static_assert(get_llvm_compile_thread_limit(4, 12) == 4);
	static_assert(get_llvm_compile_thread_limit(0, 0) == 1);
	static_assert(get_savestate_compression_thread_limit(0) == 1);
	static_assert(get_savestate_compression_thread_limit(1) == 1);
	static_assert(get_savestate_compression_thread_limit(2) == 1);
	static_assert(get_savestate_compression_thread_limit(4) == 3);
	static_assert(get_savestate_compression_thread_limit(10) == 3);
	static_assert(get_soft_vram_memory_pressure(75.f) == process_memory_pressure::low);
	static_assert(get_soft_vram_memory_pressure(76.f) == process_memory_pressure::moderate);
	static_assert(get_soft_vram_memory_pressure(91.f) == process_memory_pressure::severe);
	static_assert(get_soft_vram_memory_pressure(149.f) == process_memory_pressure::severe);
	static_assert(get_soft_vram_memory_pressure(150.f) == process_memory_pressure::severe);
	static_assert(get_soft_vram_memory_pressure(183.f) == process_memory_pressure::severe);
	static_assert(get_memory_reclaim_interval_ms(process_memory_pressure::low) == 0);
	static_assert(get_memory_reclaim_interval_ms(process_memory_pressure::moderate) == 5000);
	static_assert(get_memory_reclaim_interval_ms(process_memory_pressure::severe) == 2000);
	static_assert(get_memory_reclaim_interval_ms(process_memory_pressure::fatal) == 5000);

	static_assert(get_process_memory_pressure(2'304 * process_memory_mib) == process_memory_pressure::low);
	static_assert(get_process_memory_pressure(2'048 * process_memory_mib) == process_memory_pressure::moderate);
	static_assert(get_process_memory_pressure(1'536 * process_memory_mib) == process_memory_pressure::severe);
	static_assert(get_process_memory_pressure(1'280 * process_memory_mib) == process_memory_pressure::fatal);
	static_assert(get_process_memory_pressure(0) == process_memory_pressure::fatal);

	// A state relaxes only after recovering the extra 256 MiB hysteresis band.
	static_assert(get_process_memory_pressure(1'200 * process_memory_mib, process_memory_pressure::fatal) == process_memory_pressure::fatal);
	static_assert(get_process_memory_pressure(1'400 * process_memory_mib, process_memory_pressure::fatal) == process_memory_pressure::fatal);
	static_assert(get_process_memory_pressure(1'600 * process_memory_mib, process_memory_pressure::fatal) == process_memory_pressure::severe);
	static_assert(get_process_memory_pressure(1'700 * process_memory_mib, process_memory_pressure::severe) == process_memory_pressure::severe);
	static_assert(get_process_memory_pressure(1'900 * process_memory_mib, process_memory_pressure::severe) == process_memory_pressure::moderate);
	static_assert(get_process_memory_pressure(2'200 * process_memory_mib, process_memory_pressure::moderate) == process_memory_pressure::moderate);
	static_assert(get_process_memory_pressure(2'400 * process_memory_mib, process_memory_pressure::moderate) == process_memory_pressure::low);

	static_assert(get_bounded_reclaim_pressure(process_memory_pressure::fatal, false) == process_memory_pressure::fatal);
	static_assert(get_bounded_reclaim_pressure(process_memory_pressure::fatal, true) == process_memory_pressure::severe);
	static_assert(get_bounded_reclaim_pressure(process_memory_pressure::severe, true) == process_memory_pressure::severe);
	static_assert(!should_rearm_destructive_reclaim(process_memory_pressure::fatal));
	static_assert(!should_rearm_destructive_reclaim(process_memory_pressure::severe));
	static_assert(should_rearm_destructive_reclaim(process_memory_pressure::moderate));
	static_assert(should_rearm_destructive_reclaim(process_memory_pressure::low));

	static_assert(!has_safe_savestate_headroom(1536 * process_memory_mib));
	static_assert(has_safe_savestate_headroom(1536 * process_memory_mib + 1));
	static_assert(get_process_pressure_texture_cache_quota(559 * process_memory_mib, process_memory_pressure::low) == 559 * process_memory_mib);
	static_assert(get_process_pressure_texture_cache_quota(559 * process_memory_mib, process_memory_pressure::moderate) == 384 * process_memory_mib);
	static_assert(get_process_pressure_texture_cache_quota(559 * process_memory_mib, process_memory_pressure::severe) == 256 * process_memory_mib);
	static_assert(get_process_pressure_texture_cache_quota(559 * process_memory_mib, process_memory_pressure::fatal) == 128 * process_memory_mib);
	static_assert(get_process_pressure_texture_cache_quota(96 * process_memory_mib, process_memory_pressure::fatal) == 96 * process_memory_mib);

	assert(get_process_memory_pressure(1'000 * process_memory_mib, process_memory_pressure::moderate) == process_memory_pressure::fatal);
}
