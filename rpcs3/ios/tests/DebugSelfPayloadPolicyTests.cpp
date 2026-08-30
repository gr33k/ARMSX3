#include "Crypto/DebugSelfPayloadPolicy.h"

int main()
{
	using namespace ps3::crypto;

	static_assert(has_elf_magic(0x7f, 'E', 'L', 'F'));
	static_assert(!has_elf_magic('S', 'C', 'E', 0));
	static_assert(has_zlib_header(0x78, 0x9c));
	static_assert(has_zlib_header(0x78, 0xda));
	static_assert(!has_zlib_header(0x78, 0x00));
	static_assert(!has_zlib_header(0x7f, 'E'));

	static_assert(range_is_within_file(0x1000, 0x900, 0x700));
	static_assert(!range_is_within_file(0x1000, 0x900, 0x701));
	static_assert(!range_is_within_file(0x1000, static_cast<std::uint64_t>(-1), 1));

	static_assert(has_structured_debug_self_layout(
		0x84a820, 0x900, 0x90, 0xd0, 0x290, true));
	static_assert(!has_structured_debug_self_layout(
		0x84a820, 0x900, 0x90, 0xd0, 0x290, false));
	static_assert(!has_structured_debug_self_layout(
		0x800, 0x900, 0x90, 0xd0, 0x290, true));

	static_assert(has_valid_debug_self_segment(
		0x84a820, 0x900, 0x81b87a, 0x136c068, 2));
	static_assert(!has_valid_debug_self_segment(
		0x84a820, 0x900, 0x81b87a, 0x136c068, 3));
	static_assert(!has_valid_debug_self_segment(
		0x1000, 0xf00, 0x200, 0x800, 2));
}
