#pragma once

#include <string_view>

namespace rpcs3::ios
{
struct spu_putllc16_admission
{
	bool allowed = false;
	std::string_view reason = "unverified-pattern";
};

constexpr spu_putllc16_admission spu_putllc16_admission_for(
	std::string_view pattern_hash,
	bool ppu_reservation_priority_over_spu) noexcept
{
	// Upstream disassembled this exact cellSync ticket increment and verified
	// that it consumes and writes only the same 16-byte reservation quadword.
	if (pattern_hash == "WA0WuYLrZXrcc6Jyw5EMgYRV2bwo")
	{
		return {true, "verified-cellSync-ticket"};
	}

	// This exact CellSpurs JobChain pattern shipped through PUTLLC16 before PPU
	// reservation priority was introduced. Keep the two mechanisms exclusive:
	// priority mode relies on the global writer barrier that PUTLLC16 bypasses.
	if (pattern_hash == "620oYSe8uQqq9eTkhWfMqoEXX0us")
	{
		return {
			!ppu_reservation_priority_over_spu,
			ppu_reservation_priority_over_spu
				? "legacy-CellSpurs-pattern-conflicts-with-PPU-priority"
				: "legacy-CellSpurs-pattern-without-PPU-priority",
		};
	}

	return {};
}
}
