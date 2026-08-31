#pragma once

#include <algorithm>
#include <cstdint>

namespace rpcs3::ios::audio
{
constexpr std::uint32_t callback_byte_count(
	std::uint32_t frame_count,
	std::uint32_t bytes_per_frame,
	std::uint32_t buffer_capacity) noexcept
{
	const std::uint64_t requested =
		static_cast<std::uint64_t>(frame_count) * bytes_per_frame;
	return static_cast<std::uint32_t>(std::min<std::uint64_t>(requested, buffer_capacity));
}

constexpr std::uint32_t aligned_written_byte_count(
	std::uint32_t written,
	std::uint32_t requested,
	std::uint32_t bytes_per_frame) noexcept
{
	if (bytes_per_frame == 0)
	{
		return 0;
	}

	const std::uint32_t clamped = std::min(written, requested);
	return clamped - clamped % bytes_per_frame;
}

constexpr std::uint32_t underrun_fade_frame_count(std::uint32_t missing_frames) noexcept
{
	constexpr std::uint32_t max_fade_frames = 64;
	return std::min(missing_frames, max_fade_frames);
}

constexpr float underrun_fade_gain(
	std::uint32_t frame_index,
	std::uint32_t fade_frames) noexcept
{
	if (fade_frames == 0 || frame_index >= fade_frames)
	{
		return 0.f;
	}

	return static_cast<float>(fade_frames - frame_index - 1) /
		static_cast<float>(fade_frames);
}
}
