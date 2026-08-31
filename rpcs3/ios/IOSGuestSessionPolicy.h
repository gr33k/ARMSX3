#pragma once

#include <cstdint>

namespace rpcs3::ios
{
enum class guest_session_phase : std::uint8_t
{
	idle,
	active,
	stop_requested,
	cleanup_queued,
	cleanup_armed,
};

constexpr std::uint64_t next_guest_session_generation(std::uint64_t current) noexcept
{
	const std::uint64_t next = current + 1;
	return next ? next : 1;
}

constexpr bool owns_guest_session_generation(
	bool claimed,
	std::uint64_t current,
	std::uint64_t expected) noexcept
{
	return claimed && expected != 0 && current == expected;
}

constexpr bool can_continue_guest_session(
	bool claimed,
	guest_session_phase phase,
	std::uint64_t current,
	std::uint64_t expected) noexcept
{
	return phase == guest_session_phase::active &&
		owns_guest_session_generation(claimed, current, expected);
}

constexpr bool should_release_guest_session_on_stop(
	guest_session_phase phase,
	bool has_followup_callback) noexcept
{
	return phase == guest_session_phase::cleanup_armed ||
		(phase == guest_session_phase::active && !has_followup_callback);
}

constexpr bool should_queue_guest_session_cleanup(guest_session_phase phase) noexcept
{
	return phase == guest_session_phase::stop_requested;
}

constexpr bool should_arm_guest_session_cleanup(guest_session_phase phase) noexcept
{
	return phase == guest_session_phase::cleanup_queued;
}

constexpr guest_session_phase request_guest_session_stop_phase(
	guest_session_phase phase) noexcept
{
	return phase == guest_session_phase::idle || phase == guest_session_phase::active
		? guest_session_phase::stop_requested
		: phase;
}

constexpr guest_session_phase queue_guest_session_cleanup_phase(
	guest_session_phase phase) noexcept
{
	return phase == guest_session_phase::stop_requested
		? guest_session_phase::cleanup_queued
		: phase;
}

constexpr guest_session_phase arm_guest_session_cleanup_phase(
	guest_session_phase phase) noexcept
{
	return phase == guest_session_phase::cleanup_queued
		? guest_session_phase::cleanup_armed
		: phase;
}

constexpr guest_session_phase roll_back_guest_session_cleanup_phase(
	guest_session_phase phase) noexcept
{
	return phase == guest_session_phase::cleanup_queued ||
		phase == guest_session_phase::cleanup_armed
		? guest_session_phase::stop_requested
		: phase;
}

constexpr guest_session_phase finish_guest_session_cleanup_phase(
	guest_session_phase phase) noexcept
{
	return phase == guest_session_phase::cleanup_armed
		? guest_session_phase::idle
		: phase;
}

constexpr bool guest_session_cleanup_must_wait(
	std::uint32_t boot_operations) noexcept
{
	return boot_operations != 0;
}
}
