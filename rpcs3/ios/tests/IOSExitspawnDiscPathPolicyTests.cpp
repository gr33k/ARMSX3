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
}
