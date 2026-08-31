#pragma once

#include <cstdint>

namespace rpcs3::ios
{
	enum class process_memory_pressure : std::uint8_t
	{
		low,
		moderate,
		severe,
		fatal,
	};

	inline constexpr std::uint64_t process_memory_mib = 0x100000ull;
	inline constexpr std::uint32_t automatic_llvm_compile_threads = 3;
	inline constexpr std::uint32_t automatic_llvm_compile_threads_high_headroom = 4;
	inline constexpr std::uint32_t savestate_compression_threads = 3;

	// LLVM compilation has a large transient working set. On iOS, a zero
	// configuration value means a memory-safe automatic limit instead of every
	// performance core; an explicit value remains an opt-in override.
	constexpr std::uint32_t get_llvm_compile_thread_limit(
		std::uint32_t available_threads,
		std::uint32_t configured_threads)
	{
		const std::uint32_t hardware_limit = available_threads ? available_threads : 1;
		const std::uint32_t requested_threads = configured_threads
			? configured_threads
			: automatic_llvm_compile_threads;
		return requested_threads < hardware_limit ? requested_threads : hardware_limit;
	}

	// Every ZSTD savestate worker can temporarily own both an uncompressed input
	// block and its compression-bound output. Keep enough parallelism to avoid a
	// single-threaded multi-gigabyte save without scaling that transient working
	// set to every performance core on unified-memory devices.
	constexpr std::uint32_t get_savestate_compression_thread_limit(
		std::uint32_t available_threads)
	{
		const std::uint32_t worker_limit = available_threads > 1 ? available_threads - 1 : 1;
		return worker_limit < savestate_compression_threads
			? worker_limit
			: savestate_compression_threads;
	}

	// iOS reports the process's current dirty-memory allowance rather than a
	// fixed device-wide limit. Enter pressure states immediately, but require an
	// additional 256 MiB before relaxing them so cache reclamation cannot flap at
	// a threshold from one frame to the next.
	inline constexpr std::uint64_t process_headroom_moderate_enter = 2048 * process_memory_mib;
	inline constexpr std::uint64_t process_headroom_moderate_exit = 2304 * process_memory_mib;
	inline constexpr std::uint64_t process_headroom_severe_enter = 1536 * process_memory_mib;
	inline constexpr std::uint64_t process_headroom_severe_exit = 1792 * process_memory_mib;
	inline constexpr std::uint64_t process_headroom_fatal_enter = 1280 * process_memory_mib;
	inline constexpr std::uint64_t process_headroom_fatal_exit = 1536 * process_memory_mib;
	inline constexpr std::uint64_t texture_cache_quota_moderate = 384 * process_memory_mib;
	inline constexpr std::uint64_t texture_cache_quota_severe = 256 * process_memory_mib;
	inline constexpr std::uint64_t texture_cache_quota_fatal = 128 * process_memory_mib;

	// Cold PPU/SPU compilation can use one additional worker while the process
	// still has ample headroom. Runtime-discovered modules automatically fall
	// back before their LLVM allocations can compete with the live guest/RSX
	// working set. Explicit user limits remain honored inside the same pressure
	// caps.
	constexpr std::uint32_t get_adaptive_llvm_compile_thread_limit(
		std::uint32_t available_threads,
		std::uint32_t configured_threads,
		std::uint64_t available_memory_bytes)
	{
		const std::uint32_t hardware_limit = available_threads ? available_threads : 1;
		const std::uint32_t requested_threads = configured_threads
			? configured_threads
			: automatic_llvm_compile_threads_high_headroom;
		const std::uint32_t compile_limit = requested_threads < hardware_limit
			? requested_threads
			: hardware_limit;

		if (available_memory_bytes <= process_headroom_severe_exit)
		{
			return 1;
		}

		if (available_memory_bytes <= process_headroom_moderate_exit)
		{
			return compile_limit < 2 ? compile_limit : 2;
		}

		return compile_limit;
	}

	// The iOS VRAM budget is a proactive unified-memory target, not a hard heap
	// ceiling. Physical V0.10 evidence showed that treating allocator overshoot as
	// fatal caused destructive texture eviction to oscillate around the target.
	// Real process headroom, UIKit warnings, and allocation failures retain their
	// independent fatal paths.
	constexpr process_memory_pressure get_soft_vram_memory_pressure(float usage_percent)
	{
		if (usage_percent > 90.f)
		{
			return process_memory_pressure::severe;
		}
		if (usage_percent > 75.f)
		{
			return process_memory_pressure::moderate;
		}
		return process_memory_pressure::low;
	}

	// Reclaim is a frame-boundary synchronization point. Severity transitions and
	// UIKit warnings run immediately; persistent fatal pressure is paced so a
	// hard queue drain cannot consume every frame while heap relief continues.
	constexpr std::uint32_t get_memory_reclaim_interval_ms(process_memory_pressure pressure)
	{
		switch (pressure)
		{
		case process_memory_pressure::low: return 0;
		case process_memory_pressure::moderate: return 5000;
		case process_memory_pressure::severe: return 2000;
		case process_memory_pressure::fatal: return 5000;
		}

		return 5000;
	}

	// A fatal reclaim drains the Metal queue and invalidates inactive textures.
	// Run it once per pressure episode, then keep using the cheaper severe path
	// until headroom recovers through the severe-state hysteresis band.
	constexpr process_memory_pressure get_bounded_reclaim_pressure(
		process_memory_pressure requested,
		bool destructive_reclaim_completed)
	{
		return requested == process_memory_pressure::fatal && destructive_reclaim_completed
			? process_memory_pressure::severe
			: requested;
	}

	constexpr bool should_rearm_destructive_reclaim(process_memory_pressure process_pressure)
	{
		return process_pressure <= process_memory_pressure::moderate;
	}

	constexpr process_memory_pressure get_process_memory_pressure(
		std::uint64_t available_bytes,
		process_memory_pressure current = process_memory_pressure::low)
	{
		process_memory_pressure entered = process_memory_pressure::low;
		if (available_bytes <= process_headroom_fatal_enter)
		{
			entered = process_memory_pressure::fatal;
		}
		else if (available_bytes <= process_headroom_severe_enter)
		{
			entered = process_memory_pressure::severe;
		}
		else if (available_bytes <= process_headroom_moderate_enter)
		{
			entered = process_memory_pressure::moderate;
		}

		if (entered > current)
		{
			return entered;
		}

		switch (current)
		{
		case process_memory_pressure::fatal:
			if (available_bytes <= process_headroom_fatal_exit)
			{
				return process_memory_pressure::fatal;
			}
			[[fallthrough]];
		case process_memory_pressure::severe:
			if (available_bytes <= process_headroom_severe_exit)
			{
				return process_memory_pressure::severe;
			}
			[[fallthrough]];
		case process_memory_pressure::moderate:
			if (available_bytes <= process_headroom_moderate_exit)
			{
				return process_memory_pressure::moderate;
			}
			[[fallthrough]];
		case process_memory_pressure::low:
			return entered;
		}

		return entered;
	}

	constexpr bool has_safe_savestate_headroom(std::uint64_t available_bytes)
	{
		// Streaming compression is bounded, but committing guest/RSX state can
		// still temporarily consume hundreds of MiB. Do not destructively stop a
		// live game to save once the process has entered severe pressure.
		return available_bytes > process_headroom_severe_enter;
	}

	constexpr std::uint64_t get_process_pressure_texture_cache_quota(
		std::uint64_t normal_quota_bytes,
		process_memory_pressure pressure)
	{
		switch (pressure)
		{
		case process_memory_pressure::low:
			return normal_quota_bytes;
		case process_memory_pressure::moderate:
			return normal_quota_bytes < texture_cache_quota_moderate
				? normal_quota_bytes
				: texture_cache_quota_moderate;
		case process_memory_pressure::severe:
			return normal_quota_bytes < texture_cache_quota_severe
				? normal_quota_bytes
				: texture_cache_quota_severe;
		case process_memory_pressure::fatal:
			return normal_quota_bytes < texture_cache_quota_fatal
				? normal_quota_bytes
				: texture_cache_quota_fatal;
		}

		return texture_cache_quota_fatal;
	}
}
