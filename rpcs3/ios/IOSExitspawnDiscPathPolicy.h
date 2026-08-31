#pragma once

#include <string>
#include <string_view>
#include <cstdint>

namespace rpcs3::ios
{
inline constexpr std::string_view exitspawn_disc_legacy_prefix = "/dev_hdd0/game/PS3_GAME";
inline constexpr std::string_view exitspawn_disc_native_prefix = "/dev_bdvd/PS3_GAME";
inline constexpr std::string_view gta_v_disc_title_id = "BLES01807";
inline constexpr std::string_view gta_v_streamed_install_prefix =
	"/dev_hdd0/game/BLES01807_install/USRDIR";
inline constexpr std::string_view disc_usrdir_prefix = "/dev_bdvd/PS3_GAME/USRDIR";
inline constexpr std::string_view disc_eboot_suffix = "/USRDIR/EBOOT.BIN";
inline constexpr std::string_view preserved_disc_eboot_suffix = "/USRDIR/EBOOT.BIN.ORIG";
inline constexpr std::string_view virtual_iso_device_prefix = "/vfsv0_virtual_iso_overlay_fs_dev";
inline constexpr std::string_view virtual_netiso_device_prefix = "/vfsv0_virtual_netiso_overlay_fs_dev";

constexpr bool should_boot_preserved_disc_eboot(
	std::string_view title_id,
	bool has_standard_eboot,
	bool has_preserved_eboot) noexcept
{
	return title_id == gta_v_disc_title_id && has_standard_eboot && has_preserved_eboot;
}

constexpr bool path_has_prefix_boundary(
	std::string_view path,
	std::string_view prefix) noexcept
{
	return path.starts_with(prefix) &&
		(path.size() == prefix.size() || path[prefix.size()] == '/');
}

constexpr bool is_virtual_disc_source(std::string_view path) noexcept
{
	return path_has_prefix_boundary(path, virtual_iso_device_prefix) ||
		path_has_prefix_boundary(path, virtual_netiso_device_prefix);
}

constexpr bool should_mount_exitspawn_disc_alias(
	std::string_view title_id,
	bool is_child_process,
	bool is_netiso_session,
	std::uint64_t session_generation,
	std::string_view disc_game_path) noexcept
{
	return title_id == gta_v_disc_title_id && is_child_process &&
		is_netiso_session && session_generation != 0 &&
		is_virtual_disc_source(disc_game_path);
}

constexpr bool should_mount_streamed_install_alias(
	std::string_view title_id,
	bool is_netiso_session,
	std::uint64_t session_generation,
	std::string_view disc_usrdir_path) noexcept
{
	return title_id == gta_v_disc_title_id && is_netiso_session &&
		session_generation != 0 && is_virtual_disc_source(disc_usrdir_path);
}

struct exitspawn_disc_alias_state
{
	std::uint64_t generation = 0;

	constexpr bool active() const noexcept
	{
		return generation != 0;
	}

	constexpr void activate(std::uint64_t value) noexcept
	{
		generation = value;
	}

	constexpr bool clear() noexcept
	{
		const bool was_active = active();
		generation = 0;
		return was_active;
	}
};

constexpr bool should_redirect_exitspawn_disc_path(
	std::string_view path,
	bool is_child_process,
	bool has_virtual_iso_disc) noexcept
{
	if (!is_child_process || !has_virtual_iso_disc ||
		!path_has_prefix_boundary(path, exitspawn_disc_legacy_prefix))
	{
		return false;
	}

	return true;
}

inline std::string redirect_exitspawn_disc_path(std::string_view path)
{
	return std::string(exitspawn_disc_native_prefix) +
		std::string(path.substr(exitspawn_disc_legacy_prefix.size()));
}

inline std::string resolve_exitspawn_disc_path(
	std::string_view path,
	bool is_child_process,
	bool has_virtual_iso_disc)
{
	return should_redirect_exitspawn_disc_path(path, is_child_process, has_virtual_iso_disc)
		? redirect_exitspawn_disc_path(path)
		: std::string(path);
}

struct exitspawn_path_resolution
{
	std::string guest_argv0;
	std::string executable_lookup;
};

inline exitspawn_path_resolution resolve_exitspawn_paths(
	std::string_view path,
	bool is_child_process,
	bool has_virtual_iso_disc)
{
	return {
		std::string(path),
		resolve_exitspawn_disc_path(path, is_child_process, has_virtual_iso_disc),
	};
}
}
