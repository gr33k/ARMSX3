#include "ios/IOSAudioBufferContract.h"

#include <cassert>
#include <cstdint>
#include <limits>

int main()
{
	using rpcs3::ios::audio::aligned_written_byte_count;
	using rpcs3::ios::audio::callback_byte_count;
	using rpcs3::ios::audio::underrun_fade_frame_count;
	using rpcs3::ios::audio::underrun_fade_gain;

	static_assert(callback_byte_count(512, 8, 4096) == 4096);
	static_assert(callback_byte_count(512, 8, 2048) == 2048);
	static_assert(callback_byte_count(0, 8, 4096) == 0);
	static_assert(callback_byte_count(512, 0, 4096) == 0);
	static_assert(callback_byte_count(
		std::numeric_limits<std::uint32_t>::max(),
		std::numeric_limits<std::uint32_t>::max(),
		4096) == 4096);

	static_assert(aligned_written_byte_count(4096, 4096, 8) == 4096);
	static_assert(aligned_written_byte_count(4097, 4096, 8) == 4096);
	static_assert(aligned_written_byte_count(15, 64, 8) == 8);
	static_assert(aligned_written_byte_count(15, 64, 0) == 0);
	static_assert(underrun_fade_frame_count(0) == 0);
	static_assert(underrun_fade_frame_count(32) == 32);
	static_assert(underrun_fade_frame_count(512) == 64);
	static_assert(underrun_fade_gain(0, 64) == 63.f / 64.f);
	static_assert(underrun_fade_gain(63, 64) == 0.f);
	static_assert(underrun_fade_gain(64, 64) == 0.f);
	static_assert(underrun_fade_gain(0, 0) == 0.f);

	assert(callback_byte_count(256, 4, 1024) == 1024);
	assert(aligned_written_byte_count(1023, 1024, 4) == 1020);
	assert(underrun_fade_frame_count(128) == 64);
	return 0;
}
