#pragma once

#include <algorithm>
#include <cstdint>

namespace rpcs3::ios::storage
{
	inline constexpr std::uint64_t safety_reserve_bytes = 1ull << 30;
	inline constexpr std::uint64_t guest_compatibility_cap_bytes =
		40ull * 1024 * 1024 * 1024 - 256ull * 1024;

	constexpr std::uint64_t effective_available_bytes(
		std::uint64_t immediately_available_bytes,
		std::uint64_t important_usage_available_bytes) noexcept
	{
		return std::max(immediately_available_bytes, important_usage_available_bytes);
	}

	constexpr std::uint64_t writable_bytes(std::uint64_t available_bytes) noexcept
	{
		return available_bytes > safety_reserve_bytes
			? available_bytes - safety_reserve_bytes
			: 0;
	}

	constexpr std::uint64_t guest_reported_bytes(std::uint64_t available_bytes) noexcept
	{
		return std::min(writable_bytes(available_bytes), guest_compatibility_cap_bytes);
	}

	constexpr std::int32_t guest_reported_kib(std::uint64_t available_bytes) noexcept
	{
		return static_cast<std::int32_t>(guest_reported_bytes(available_bytes) / 1024);
	}
}
