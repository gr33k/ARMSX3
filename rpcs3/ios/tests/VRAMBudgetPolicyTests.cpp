#include "Emu/RSX/VK/vkutils/VRAMBudgetPolicy.h"

#include <cassert>
#include <cstdint>

namespace
{
	constexpr std::uint64_t mib = vk::vram_budget_mib;
	constexpr std::uint64_t gib = 1024 * mib;
}

int main()
{
	constexpr auto configured_desktop_default = 64 * gib;

#ifdef RPCS3_IOS
	static_assert(vk::get_effective_vram_pressure_limit(7461 * mib, configured_desktop_default) == 1492 * mib);
	static_assert(vk::get_effective_vram_pressure_limit(8 * gib, configured_desktop_default) == 1638 * mib);
	static_assert(vk::get_effective_vram_pressure_limit(6 * gib, configured_desktop_default) == 1228 * mib);
	static_assert(vk::get_effective_vram_pressure_limit(12 * gib, configured_desktop_default) == 2457 * mib);
	static_assert(vk::get_effective_vram_pressure_limit(16 * gib, configured_desktop_default) == 3 * gib);
	static_assert(vk::get_effective_vram_pressure_limit(4 * gib, configured_desktop_default) == 1 * gib);
	static_assert(vk::get_effective_vram_pressure_limit(512 * mib, configured_desktop_default) == 512 * mib);
	static_assert(vk::get_effective_vram_pressure_limit(8 * gib, 512 * mib) == 512 * mib);
	static_assert(vk::get_requested_vram_allocation_limit(7461 * mib, configured_desktop_default) == 7461 * mib);
	static_assert(vk::get_requested_vram_allocation_limit(8 * gib, 512 * mib) == 512 * mib);

	assert(vk::get_effective_vram_pressure_limit(12 * gib, configured_desktop_default) >
		vk::get_effective_vram_pressure_limit(8 * gib, configured_desktop_default));
#else
	static_assert(vk::get_effective_vram_pressure_limit(8 * gib, configured_desktop_default) == 8 * gib);
	static_assert(vk::get_effective_vram_pressure_limit(8 * gib, 512 * mib) == 512 * mib);
	static_assert(vk::get_effective_vram_pressure_limit(0, configured_desktop_default) == 0);

	assert(vk::get_effective_vram_pressure_limit(6 * gib, configured_desktop_default) == 6 * gib);
#endif

	static_assert(vk::get_available_vram_budget(2 * gib, 1 * gib) == 1 * gib);
	static_assert(vk::get_available_vram_budget(2 * gib, 2 * gib) == 0);
	static_assert(vk::get_available_vram_budget(2 * gib, 3 * gib) == 0);
}
