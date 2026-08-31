#pragma once

#include <string>
#include <string_view>

namespace rpcs3::ios
{
inline constexpr std::string_view exitspawn_disc_legacy_prefix = "/dev_hdd0/game/PS3_GAME";
inline constexpr std::string_view exitspawn_disc_native_prefix = "/dev_bdvd/PS3_GAME";

constexpr bool should_redirect_exitspawn_disc_path(
	std::string_view path,
	bool is_child_process,
	bool has_virtual_iso_disc) noexcept
{
	if (!is_child_process || !has_virtual_iso_disc || !path.starts_with(exitspawn_disc_legacy_prefix))
	{
		return false;
	}

	return path.size() == exitspawn_disc_legacy_prefix.size() ||
		path[exitspawn_disc_legacy_prefix.size()] == '/';
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
