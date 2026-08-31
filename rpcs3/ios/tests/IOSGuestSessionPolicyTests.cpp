#include "rpcs3/ios/IOSGuestSessionPolicy.h"

#include <cassert>
#include <limits>

int main()
{
	using rpcs3::ios::next_guest_session_generation;
	using rpcs3::ios::arm_guest_session_cleanup_phase;
	using rpcs3::ios::can_continue_guest_session;
	using rpcs3::ios::finish_guest_session_cleanup_phase;
	using rpcs3::ios::guest_session_cleanup_must_wait;
	using rpcs3::ios::guest_session_phase;
	using rpcs3::ios::owns_guest_session_generation;
	using rpcs3::ios::queue_guest_session_cleanup_phase;
	using rpcs3::ios::request_guest_session_stop_phase;
	using rpcs3::ios::roll_back_guest_session_cleanup_phase;
	using rpcs3::ios::should_arm_guest_session_cleanup;
	using rpcs3::ios::should_queue_guest_session_cleanup;
	using rpcs3::ios::should_release_guest_session_on_stop;

	static_assert(next_guest_session_generation(0) == 1);
	static_assert(next_guest_session_generation(41) == 42);
	static_assert(next_guest_session_generation(std::numeric_limits<std::uint64_t>::max()) == 1);
	static_assert(owns_guest_session_generation(true, 42, 42));
	static_assert(!owns_guest_session_generation(false, 42, 42));
	static_assert(!owns_guest_session_generation(true, 42, 0));
	static_assert(!owns_guest_session_generation(true, 42, 41));
	static_assert(can_continue_guest_session(true, guest_session_phase::active, 42, 42));
	static_assert(!can_continue_guest_session(true, guest_session_phase::stop_requested, 42, 42));
	static_assert(!can_continue_guest_session(true, guest_session_phase::cleanup_queued, 42, 42));
	static_assert(!can_continue_guest_session(true, guest_session_phase::cleanup_armed, 42, 42));
	static_assert(!can_continue_guest_session(false, guest_session_phase::active, 42, 42));
	static_assert(!can_continue_guest_session(true, guest_session_phase::active, 42, 41));

	// A normal exitspawn stop retains ownership until its child callback runs.
	static_assert(!should_release_guest_session_on_stop(
		guest_session_phase::active, true));
	// A terminal child crash has no follow-up callback and releases the gate.
	static_assert(should_release_guest_session_on_stop(
		guest_session_phase::active, false));
	// Stop requested before the serialized cleanup task must remain fail-closed.
	static_assert(!should_release_guest_session_on_stop(
		guest_session_phase::stop_requested, false));
	static_assert(!should_release_guest_session_on_stop(
		guest_session_phase::cleanup_queued, false));
	// Once cleanup is armed, on_stop owns final release even if a callback existed.
	static_assert(should_release_guest_session_on_stop(
		guest_session_phase::cleanup_armed, true));
	static_assert(!should_release_guest_session_on_stop(
		guest_session_phase::idle, false));

	// Only one queued cleanup may own the main-thread handoff. A failed queue
	// rolls back to stop_requested, which is the sole retryable phase.
	static_assert(should_queue_guest_session_cleanup(guest_session_phase::stop_requested));
	static_assert(!should_queue_guest_session_cleanup(guest_session_phase::cleanup_queued));
	static_assert(!should_queue_guest_session_cleanup(guest_session_phase::cleanup_armed));
	static_assert(should_arm_guest_session_cleanup(guest_session_phase::cleanup_queued));
	static_assert(!should_arm_guest_session_cleanup(guest_session_phase::stop_requested));
	static_assert(!should_arm_guest_session_cleanup(guest_session_phase::cleanup_armed));

	constexpr auto requested = request_guest_session_stop_phase(guest_session_phase::active);
	static_assert(requested == guest_session_phase::stop_requested);
	constexpr auto queued = queue_guest_session_cleanup_phase(requested);
	static_assert(queued == guest_session_phase::cleanup_queued);
	// A duplicate queue request cannot advance or duplicate the owner.
	static_assert(queue_guest_session_cleanup_phase(queued) == queued);
	constexpr auto armed = arm_guest_session_cleanup_phase(queued);
	static_assert(armed == guest_session_phase::cleanup_armed);
	static_assert(finish_guest_session_cleanup_phase(armed) == guest_session_phase::idle);
	// Dispatch failure is retryable but cannot reopen the launch gate.
	static_assert(roll_back_guest_session_cleanup_phase(queued) ==
		guest_session_phase::stop_requested);
	static_assert(roll_back_guest_session_cleanup_phase(armed) ==
		guest_session_phase::stop_requested);
	static_assert(request_guest_session_stop_phase(guest_session_phase::cleanup_armed) ==
		guest_session_phase::cleanup_armed);
	static_assert(!guest_session_cleanup_must_wait(0));
	static_assert(guest_session_cleanup_must_wait(1));
	static_assert(guest_session_cleanup_must_wait(2));

	assert(next_guest_session_generation(99) == 100);
}
