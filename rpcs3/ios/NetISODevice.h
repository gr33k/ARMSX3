#pragma once

#include "NetISOProtocol.h"
#include "Utilities/File.h"

#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace rpcs3::ios
{
class netiso_backing;

enum class netiso_game_kind : u32
{
	iso = 1,
	extracted_folder = 2,
};

struct netiso_game_entry
{
	std::string remote_path;
	std::string display_name;
	netiso_game_kind kind = netiso_game_kind::iso;
	u64 size = 0;
};

struct netiso_game_metadata
{
	std::string virtual_path;
	std::string title_id;
	std::string title;
	u64 size = 0;
};

struct netiso_statistics
{
	u64 remote_bytes = 0;
	u64 logical_bytes = 0;
	u64 cached_bytes = 0;
	u64 remote_reads = 0;
	u64 cache_hits = 0;
	u64 reconnects = 0;
};

class netiso_device final : public fs::device_base
{
public:
	inline static constexpr std::string_view virtual_device_name =
		"/vfsv0_virtual_netiso_overlay_fs_dev";
	inline static constexpr std::string_view registry_name = "netiso_overlay_fs_dev";

	explicit netiso_device(netiso::endpoint server);
	~netiso_device() override = default;

	const netiso::endpoint& server() const noexcept;
	std::string virtual_path(const std::string& remote_path) const;
	bool list_remote(const std::string& remote_path,
		std::vector<netiso::directory_entry>& entries, std::string& error) const;
	std::string last_error() const;

	bool stat(const std::string& path, fs::stat_t& info) override;
	bool statfs(const std::string& path, fs::device_stat& info) override;
	std::unique_ptr<fs::file_base> open(
		const std::string& path, bs_t<fs::open_mode> mode) override;
	std::unique_ptr<fs::dir_base> open_dir(const std::string& path) override;

private:
	bool remote_path(const std::string& path, std::string& remote, std::string& error) const;
	std::shared_ptr<netiso_backing> acquire_backing(
		const std::string& remote_path, std::string& error);
	void remember_error(std::string error) const;

	netiso::endpoint m_server;
	std::mutex m_backing_mutex;
	std::string m_virtual_backing_path;
	std::shared_ptr<netiso_backing> m_virtual_backing;
	mutable std::mutex m_error_mutex;
	mutable std::string m_last_error;
};

std::vector<netiso_game_entry> enumerate_netiso_games(
	const netiso_device& device, std::string& error);
bool inspect_netiso_game(
	const netiso_device& device,
	const std::string& remote_path,
	netiso_game_metadata& metadata,
	std::string& error);
netiso_statistics capture_netiso_statistics() noexcept;
void reset_netiso_statistics() noexcept;
}
