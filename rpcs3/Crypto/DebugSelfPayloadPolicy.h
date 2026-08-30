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

constexpr bool range_is_within_file(
	std::uint64_t file_size,
	std::uint64_t offset,
	std::uint64_t size) noexcept
{
	return offset <= file_size && size <= file_size - offset;
}

constexpr bool has_structured_debug_self_layout(
	std::uint64_t file_size,
	std::uint64_t header_size,
	std::uint64_t elf_header_offset,
	std::uint64_t program_header_offset,
	std::uint64_t segment_table_offset,
	bool embedded_elf_magic) noexcept
{
	return embedded_elf_magic && header_size <= file_size &&
		range_is_within_file(header_size, elf_header_offset, 64) &&
		range_is_within_file(header_size, program_header_offset, 1) &&
		range_is_within_file(header_size, segment_table_offset, 1);
}

constexpr bool has_valid_debug_self_segment(
	std::uint64_t file_size,
	std::uint64_t offset,
	std::uint64_t stored_size,
	std::uint64_t output_size,
	std::uint32_t compression) noexcept
{
	return output_size && stored_size &&
		(compression == 1 || compression == 2) &&
		range_is_within_file(file_size, offset, stored_size);
}
}
