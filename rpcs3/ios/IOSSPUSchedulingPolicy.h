#pragma once

#include <algorithm>
#include <cstdint>
#include <string_view>

namespace rpcs3::ios
{
constexpr bool automatic_mobile_spu_scheduling_for_title(std::string_view title_id) noexcept
{
	// Uncharted 1 streams SPU jobs during gameplay and otherwise starves those
	// jobs behind the two background compiler workers on six-thread iPhones.
	return title_id == "BCES00065";
}

constexpr std::uint32_t spu_compile_free_thread_floor(
	std::uint32_t hardware_threads,
	bool mobile_scheduling) noexcept
{
	if (mobile_scheduling && hardware_threads <= 10)
	{
		return std::max<std::uint32_t>(1, hardware_threads / 2);
	}

	return hardware_threads > 10 ? hardware_threads - 10 : 0;
}
}
