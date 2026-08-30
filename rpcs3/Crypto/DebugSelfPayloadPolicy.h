#pragma once

#include <cstdint>

namespace ps3::crypto
{
constexpr bool has_elf_magic(
	std::uint8_t first,
	std::uint8_t second,
	std::uint8_t third,
	std::uint8_t fourth) noexcept
{
	return first == 0x7f && second == 'E' && third == 'L' && fourth == 'F';
}

constexpr bool has_zlib_header(std::uint8_t cmf, std::uint8_t flg) noexcept
{
	return (cmf & 0x0f) == 8 && (cmf >> 4) <= 7 &&
		((static_cast<std::uint16_t>(cmf) << 8) | flg) % 31 == 0;
}
}
