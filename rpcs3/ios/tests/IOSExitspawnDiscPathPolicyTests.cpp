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
	static_assert(path_has_prefix_boundary(
		"/dev_hdd0/game/PS3_GAME/USRDIR/common.edat", exitspawn_disc_legacy_prefix));
	static_assert(!path_has_prefix_boundary(
		"/dev_hdd0/game/PS3_GAMEX/USRDIR/common.edat", exitspawn_disc_legacy_prefix));
	static_assert(is_virtual_disc_source(
		"/vfsv0_virtual_iso_overlay_fs_dev/PS3_GAME"));
	static_assert(is_virtual_disc_source(
		"/vfsv0_virtual_netiso_overlay_fs_dev/***PS3***/GAMES/BLES01807-[Grand Theft Auto V]"));
	static_assert(!is_virtual_disc_source(
		"/vfsv0_virtual_iso_overlay_fs_device/PS3_GAME"));
	static_assert(should_boot_preserved_disc_eboot(
		"BLES01807", true, true));
	static_assert(!should_boot_preserved_disc_eboot(
		"BLUS31156", true, true));
	static_assert(!should_boot_preserved_disc_eboot(
		"BLES01807", true, false));
	static_assert(!should_boot_preserved_disc_eboot(
		"BLES01807", false, true));
	static_assert(disc_eboot_suffix == "/USRDIR/EBOOT.BIN");
	static_assert(preserved_disc_eboot_suffix == "/USRDIR/EBOOT.BIN.ORIG");

	// Physical V0.28 evidence: BLES01807's duplex.self probes this exact
	// pseudo-HDD tree. Only its serialized NETISO child may receive the alias.
	static_assert(should_mount_exitspawn_disc_alias(
		"BLES01807", true, true, 42,
		"/vfsv0_virtual_iso_overlay_fs_dev/PS3_GAME"));
	static_assert(!should_mount_exitspawn_disc_alias(
		"BLES01807", false, true, 42,
		"/vfsv0_virtual_iso_overlay_fs_dev/PS3_GAME"));
	static_assert(!should_mount_exitspawn_disc_alias(
		"BLES01807", true, false, 42,
		"/vfsv0_virtual_iso_overlay_fs_dev/PS3_GAME"));
	static_assert(!should_mount_exitspawn_disc_alias(
		"BLES01807", true, true, 0,
		"/vfsv0_virtual_iso_overlay_fs_dev/PS3_GAME"));
	static_assert(!should_mount_exitspawn_disc_alias(
		"BLUS31156", true, true, 42,
		"/vfsv0_virtual_iso_overlay_fs_dev/PS3_GAME"));
	static_assert(!should_mount_exitspawn_disc_alias(
		"BLES01807", true, true, 42,
		"/private/var/mobile/not-a-virtual-disc/PS3_GAME"));
	static_assert(gta_v_streamed_install_prefix ==
		"/dev_hdd0/game/BLES01807_install/USRDIR");
	static_assert(disc_usrdir_prefix == "/dev_bdvd/PS3_GAME/USRDIR");
	static_assert(should_mount_streamed_install_alias(
		"BLES01807", true, 42,
		"/vfsv0_virtual_netiso_overlay_fs_dev/***PS3***/GAMES/BLES01807-[Grand Theft Auto V]/PS3_GAME/USRDIR"));
	static_assert(should_mount_streamed_install_alias(
		"BLES01807", true, 42,
		"/vfsv0_virtual_iso_overlay_fs_dev/PS3_GAME/USRDIR"));
	static_assert(!should_mount_streamed_install_alias(
		"BLUS31156", true, 42,
		"/vfsv0_virtual_netiso_overlay_fs_dev/PS3_GAME/USRDIR"));
	static_assert(!should_mount_streamed_install_alias(
		"BLES01807", false, 42,
		"/vfsv0_virtual_netiso_overlay_fs_dev/PS3_GAME/USRDIR"));
	static_assert(!should_mount_streamed_install_alias(
		"BLES01807", true, 0,
		"/vfsv0_virtual_netiso_overlay_fs_dev/PS3_GAME/USRDIR"));
	static_assert(!should_mount_streamed_install_alias(
		"BLES01807", true, 42,
		"/private/var/mobile/not-a-virtual-disc/PS3_GAME/USRDIR"));

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

	exitspawn_disc_alias_state alias_state;
	assert(!alias_state.active());
	alias_state.activate(42);
	assert(alias_state.active());
	assert(alias_state.generation == 42);
	assert(alias_state.clear());
	assert(!alias_state.active());
	assert(!alias_state.clear());
}
