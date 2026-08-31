#pragma once

#include <cstdint>
#include <functional>

namespace rpcs3::ios
{
// Returns the generation owned by the currently launched frontend session, or
// zero when no frontend session is active.
std::uint64_t current_guest_session_generation() noexcept;

// Returns true only while the caller still owns the active frontend session.
// Exitspawn callbacks use this before mutating emulator state or booting a child.
bool owns_current_guest_session_generation(std::uint64_t expected_generation) noexcept;

// Publishes an exitspawn callback only while its frontend generation remains
// active. Stop uses the same mutex, so stale callbacks are never installed.
bool install_continuous_boot_callback(
	std::uint64_t expected_generation,
	std::function<void()> callback) noexcept;

// Releases the frontend claim only after an exitspawn child failed to boot.
// Successful continuous handoffs keep the claim and NETISO mount intact.
void handle_continuous_boot_failure(std::uint64_t expected_generation) noexcept;

// Runs from RPCS3's main-thread stop callback. Continuous handoffs retain the
// claim; terminal or explicitly requested stops release it after cleanup.
void handle_emulation_stopped() noexcept;
}
