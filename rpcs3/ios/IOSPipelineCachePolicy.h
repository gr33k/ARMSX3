#pragma once

#include <cstdint>

namespace rpcs3::ios
{
inline constexpr std::uint32_t pipeline_cache_checkpoint_pipeline_count = 64;
inline constexpr std::uint64_t pipeline_cache_checkpoint_interval_ms = 15'000;
inline constexpr std::uint64_t pipeline_cache_checkpoint_minimum_headroom = 1024ull * 1024ull * 1024ull;

constexpr bool should_checkpoint_pipeline_cache(
	std::uint32_t dirty_pipeline_count,
	std::uint64_t elapsed_ms,
	std::uint64_t process_headroom_bytes,
	bool force) noexcept
{
	if (!dirty_pipeline_count || process_headroom_bytes < pipeline_cache_checkpoint_minimum_headroom)
	{
		return false;
	}

	return force ||
		(dirty_pipeline_count >= pipeline_cache_checkpoint_pipeline_count &&
			elapsed_ms >= pipeline_cache_checkpoint_interval_ms);
}
}
