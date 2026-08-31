#include "ios/IOSStoragePolicy.h"

#include <cassert>
#include <cstdint>

int main()
{
	using namespace rpcs3::ios::storage;

	static_assert(writable_bytes(0) == 0);
	static_assert(writable_bytes(safety_reserve_bytes) == 0);
	static_assert(writable_bytes(safety_reserve_bytes + 1) == 1);
	static_assert(writable_bytes(6ull << 30) == (5ull << 30));

	static_assert(guest_reported_bytes(6ull << 30) == (5ull << 30));
	static_assert(guest_reported_bytes(128ull << 30) == guest_compatibility_cap_bytes);
	static_assert(guest_reported_kib(128ull << 30) == 40 * 1024 * 1024 - 256);

	assert(guest_reported_kib(safety_reserve_bytes + 1024) == 1);
	return 0;
}
