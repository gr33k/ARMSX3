#pragma once

#include <algorithm>
#include <cstdint>
#include <limits>

namespace rsx::texture_cache_helpers
{
	struct blit_target_height_result
	{
		std::uint32_t height;
		std::uint32_t maximum_height;
		bool constrained;
		bool representable;
	};

	constexpr blit_target_height_result constrain_blit_target_height(
		std::uint32_t proposed_height,
		std::uint32_t payload_length,
		std::uint32_t pitch,
		std::uint64_t available_length) noexcept
	{
		if (!pitch)
		{
			return {proposed_height, 0, false, false};
		}

		const auto minimum_height = static_cast<std::uint32_t>(
			(static_cast<std::uint64_t>(payload_length) + pitch - 1) / pitch);
		const auto available_rows = available_length / pitch;
		const auto maximum_height = static_cast<std::uint32_t>(std::min<std::uint64_t>(
			available_rows,
			std::numeric_limits<std::uint32_t>::max()));

		// A partial final row can fit the payload but not the rectangular cache
		// section. Let the caller use the correctness fallback in that case.
		if (available_rows < minimum_height)
		{
			return {proposed_height, maximum_height, false, false};
		}

		const auto height = std::clamp(proposed_height, minimum_height, maximum_height);
		return {height, maximum_height, height != proposed_height, true};
	}

	constexpr std::uint32_t cap_blit_target_height(
		std::uint32_t proposed_height,
		std::uint32_t maximum_height) noexcept
	{
		return std::min(proposed_height, maximum_height);
	}
}
