#include "ios/IOSExitspawnDiscPathPolicy.h"

#include <cassert>

int main()
{
	using namespace rpcs3::ios;

	static_assert(should_redirect_exitspawn_disc_path(
		"/dev_hdd0/game/PS3_GAME", true, true));
	static_assert(should_redirect_exitspawn_disc_path(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", true, true));
	static_assert(!should_redirect_exitspawn_disc_path(
		"/dev_hdd0/game/PS3_GAMEX/USRDIR/EBOOT.BIN", true, true));
	static_assert(!should_redirect_exitspawn_disc_path(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", false, true));
	static_assert(!should_redirect_exitspawn_disc_path(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", true, false));

	assert(redirect_exitspawn_disc_path("/dev_hdd0/game/PS3_GAME") ==
		"/dev_bdvd/PS3_GAME");
	assert(redirect_exitspawn_disc_path("/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN") ==
		"/dev_bdvd/PS3_GAME/USRDIR/EBOOT.BIN");
	assert(resolve_exitspawn_disc_path(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", true, true) ==
		"/dev_bdvd/PS3_GAME/USRDIR/EBOOT.BIN");
	assert(resolve_exitspawn_disc_path(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", false, true) ==
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN");
	assert(resolve_exitspawn_disc_path(
		"/dev_hdd0/game/BLUS31156/USRDIR/EBOOT.BIN", true, true) ==
		"/dev_hdd0/game/BLUS31156/USRDIR/EBOOT.BIN");

	const auto child_paths = resolve_exitspawn_paths(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", true, true);
	assert(child_paths.guest_argv0 == "/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN");
	assert(child_paths.executable_lookup == "/dev_bdvd/PS3_GAME/USRDIR/EBOOT.BIN");

	const auto initial_paths = resolve_exitspawn_paths(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", false, true);
	assert(initial_paths.guest_argv0 == "/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN");
	assert(initial_paths.executable_lookup == initial_paths.guest_argv0);

	const auto local_disc_paths = resolve_exitspawn_paths(
		"/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN", true, false);
	assert(local_disc_paths.guest_argv0 == "/dev_hdd0/game/PS3_GAME/USRDIR/EBOOT.BIN");
	assert(local_disc_paths.executable_lookup == local_disc_paths.guest_argv0);

	const auto local_paths = resolve_exitspawn_paths(
		"/dev_hdd0/game/BLUS31156/USRDIR/EBOOT.BIN", true, true);
	assert(local_paths.guest_argv0 == "/dev_hdd0/game/BLUS31156/USRDIR/EBOOT.BIN");
	assert(local_paths.executable_lookup == local_paths.guest_argv0);
}
