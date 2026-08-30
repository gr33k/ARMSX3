#pragma once

#include <cstdint>
#include <string_view>

namespace rpcs3::ios
{
enum class mobile_title_profile_kind : std::uint8_t
{
	none,
	uncharted_1,
	uncharted_2,
	uncharted_3,
	demanding_3d,
};

struct mobile_title_profile
{
	mobile_title_profile_kind kind = mobile_title_profile_kind::none;
	std::uint16_t resolution_scale_percent = 100;
	std::uint8_t shader_compiler_threads = 0;
	bool multithreaded_rsx = false;
	std::int8_t stub_ppu_traps = 0;

	constexpr explicit operator bool() const noexcept
	{
		return kind != mobile_title_profile_kind::none;
	}
};

constexpr bool is_red_dead_redemption_title(std::string_view title_id) noexcept
{
	return title_id == "BLUS30758" || title_id == "BLUS30418" ||
		title_id == "BLES01294" || title_id == "BLES00680";
}

constexpr bool is_grand_theft_auto_v_title(std::string_view title_id) noexcept
{
	return title_id == "BLES01807" || title_id == "BLUS31156";
}

constexpr mobile_title_profile mobile_profile_for_title(std::string_view title_id) noexcept
{
	if (title_id == "BCES00065" || title_id == "BCUS98103" || title_id == "BCAS20024")
	{
		return {mobile_title_profile_kind::uncharted_1, 50, 2, true, 0};
	}

	if (title_id == "BCUS98123" || title_id == "BCES00509")
	{
		return {mobile_title_profile_kind::uncharted_2, 50, 2, true, 1};
	}

	if (title_id == "BCES01175" || title_id == "BCUS98233")
	{
		// V0.14's forced RSX offload produced deterministic fragment-program
		// corruption on the physical A15. Keep the other mobile limits while
		// the underlying offload synchronization defect is isolated.
		return {mobile_title_profile_kind::uncharted_3, 50, 2, false, 0};
	}

	if (is_red_dead_redemption_title(title_id) ||
		is_grand_theft_auto_v_title(title_id))
	{
		return {mobile_title_profile_kind::demanding_3d, 50, 2, true, 0};
	}

	return {};
}
}
