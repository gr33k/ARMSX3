#include "Emu/RSX/Common/blit_target_bounds_policy.h"

#include <cassert>
#include <cstdint>
#include <limits>

int main()
{
	using rsx::texture_cache_helpers::constrain_blit_target_height;
	using rsx::texture_cache_helpers::cap_blit_target_height;

	constexpr std::uint32_t pitch = 1280 * 4;

	constexpr auto no_overflow = constrain_blit_target_height(720, 640 * pitch, pitch, 720 * pitch);
	static_assert(no_overflow.height == 720);
	static_assert(no_overflow.maximum_height == 720);
	static_assert(!no_overflow.constrained);
	static_assert(no_overflow.representable);

	constexpr auto tile_clamp = constrain_blit_target_height(1080, 640 * pitch, pitch, 720 * pitch);
	static_assert(tile_clamp.height == 720);
	static_assert(tile_clamp.constrained);
	static_assert(tile_clamp.representable);

	constexpr auto payload_floor = constrain_blit_target_height(1080, 700 * pitch, pitch, 720 * pitch);
	static_assert(payload_floor.height == 720);
	static_assert(static_cast<std::uint64_t>(payload_floor.height) * pitch >= 700ull * pitch);

	constexpr auto partial_tail = constrain_blit_target_height(1080, 640 * pitch, pitch, (720ull * pitch) - 1);
	static_assert(partial_tail.height == 719);
	static_assert(partial_tail.maximum_height == 719);
	static_assert(partial_tail.constrained);
	static_assert(partial_tail.representable);

	constexpr auto partial_payload = constrain_blit_target_height(1080, (719 * pitch) + 1, pitch, (720ull * pitch) - 1);
	static_assert(!partial_payload.representable);

	constexpr auto sub_720_tile = constrain_blit_target_height(1080, 640 * pitch, pitch, 650ull * pitch);
	constexpr auto legacy_720_guess = 720u;
	static_assert(cap_blit_target_height(legacy_720_guess, sub_720_tile.maximum_height) == 650);

	constexpr auto overflow_guard = constrain_blit_target_height(
		std::numeric_limits<std::uint32_t>::max(),
		pitch,
		pitch,
		2ull * pitch);
	static_assert(overflow_guard.height == 2);
	static_assert(overflow_guard.constrained);
	static_assert(overflow_guard.representable);

	assert(!constrain_blit_target_height(1080, 640 * pitch, 0, 720ull * pitch).representable);
	return 0;
}
