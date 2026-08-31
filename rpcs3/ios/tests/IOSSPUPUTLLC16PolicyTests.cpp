#include "ios/IOSSPUPUTLLC16Policy.h"

#include <string_view>

int main()
{
	using rpcs3::ios::spu_putllc16_admission_for;

	constexpr auto verified = spu_putllc16_admission_for(
		"WA0WuYLrZXrcc6Jyw5EMgYRV2bwo", false);
	static_assert(verified.allowed);
	static_assert(verified.reason == "verified-cellSync-ticket");

	constexpr auto legacy_without_priority = spu_putllc16_admission_for(
		"620oYSe8uQqq9eTkhWfMqoEXX0us", false);
	static_assert(legacy_without_priority.allowed);

	constexpr auto legacy_with_priority = spu_putllc16_admission_for(
		"620oYSe8uQqq9eTkhWfMqoEXX0us", true);
	static_assert(!legacy_with_priority.allowed);

	constexpr auto unknown = spu_putllc16_admission_for(
		"0ufxr18soJFU57mPncwUtGaLKHCJ", false);
	static_assert(!unknown.allowed);
}
