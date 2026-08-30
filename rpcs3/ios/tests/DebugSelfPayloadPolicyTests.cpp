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
}
