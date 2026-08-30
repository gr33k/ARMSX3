#include "NetISODevice.h"

#include "Loader/ISO.h"
#include "Loader/PSF.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cstring>
#include <limits>
#include <mutex>
#include <unordered_set>

namespace rpcs3::ios
{
namespace
{
constexpr u64 read_ahead_size = 1024 * 1024;
constexpr u64 read_ahead_alignment = 64 * 1024;
constexpr std::string_view virtual_ps3_prefix = "/***PS3***/";

struct netiso_statistics_store
{
	std::atomic<u64> remote_bytes{0};
	std::atomic<u64> logical_bytes{0};
	std::atomic<u64> cached_bytes{0};
	std::atomic<u64> remote_reads{0};
	std::atomic<u64> cache_hits{0};
	std::atomic<u64> reconnects{0};
};

netiso_statistics_store g_netiso_statistics;

fs::stat_t to_fs_stat(const netiso::file_info& remote)
{
	fs::stat_t result{};
	result.is_directory = remote.is_directory;
	result.is_writable = false;
	result.size = remote.size;
	result.mtime = static_cast<s64>(remote.mtime);
	result.ctime = static_cast<s64>(remote.ctime);
	result.atime = static_cast<s64>(remote.atime);
	return result;
}

bool is_not_found(const std::string& error)
{
	return error.find("not found") != std::string::npos ||
		error.find("could not be opened") != std::string::npos;
}

void set_fs_error(const std::string& error)
{
	fs::g_tls_error = is_not_found(error) ? fs::error::noent : fs::error::unknown;
}

bool same_identity(const netiso::file_info& left, const netiso::file_info& right)
{
	return left.size == right.size &&
		(!left.mtime || !right.mtime || left.mtime == right.mtime);
}

class netiso_file final : public fs::file_base
{
public:
	netiso_file(netiso::endpoint server, std::string path,
		netiso::file_info identity, std::unique_ptr<netiso::connection> connection)
		: m_server(std::move(server))
		, m_path(std::move(path))
		, m_identity(identity)
		, m_connection(std::move(connection))
	{
	}

	fs::stat_t get_stat() override
	{
		return to_fs_stat(m_identity);
	}

	bool trunc(u64) override
	{
		fs::g_tls_error = fs::error::readonly;
		return false;
	}

	u64 read(void* buffer, u64 size) override
	{
		std::lock_guard lock(m_mutex);
		const u64 result = read_at_locked(m_position, buffer, size);
		m_position += result;
		return result;
	}

	u64 read_at(u64 offset, void* buffer, u64 size) override
	{
		std::lock_guard lock(m_mutex);
		return read_at_locked(offset, buffer, size);
	}

	u64 write(const void*, u64) override
	{
		fs::g_tls_error = fs::error::readonly;
		return 0;
	}

	u64 seek(s64 offset, fs::seek_mode whence) override
	{
		std::lock_guard lock(m_mutex);
		const s64 base =
			whence == fs::seek_set ? 0 :
			whence == fs::seek_cur ? static_cast<s64>(m_position) :
			whence == fs::seek_end ? static_cast<s64>(m_identity.size) : -1;
		if (base < 0 || (offset < 0 && base < -offset) ||
			(offset > 0 && base > std::numeric_limits<s64>::max() - offset))
		{
			fs::g_tls_error = fs::error::inval;
			return umax;
		}
		m_position = static_cast<u64>(base + offset);
		return m_position;
	}

	u64 size() override
	{
		return m_identity.size;
	}

	fs::file_id get_id() override
	{
		std::string identity = m_server.host;
		identity.push_back('\0');
		identity += std::to_string(m_server.port);
		identity.push_back('\0');
		identity += m_path;
		identity.push_back('\0');
		identity += std::to_string(m_identity.size);
		identity.push_back('\0');
		identity += std::to_string(m_identity.mtime);
		fs::file_id result{"netiso_file"};
		result.data.assign(identity.begin(), identity.end());
		return result;
	}

private:
	bool reconnect_and_verify(std::string& error)
	{
		auto replacement = std::make_unique<netiso::connection>(m_server);
		if (!replacement->connect(error))
		{
			return false;
		}
		netiso::file_info identity{};
		if (!replacement->open_file(m_path, identity, error))
		{
			return false;
		}
		if (!same_identity(m_identity, identity))
		{
			error = "NETISO remote file changed while it was mounted";
			return false;
		}
		m_connection = std::move(replacement);
		g_netiso_statistics.reconnects.fetch_add(1, std::memory_order_relaxed);
		return true;
	}

	bool read_exact(u64 offset, void* buffer, usz size, std::string& error)
	{
		for (u32 attempt = 0; attempt < 2; attempt++)
		{
			usz received = 0;
			g_netiso_statistics.remote_reads.fetch_add(1, std::memory_order_relaxed);
			const bool succeeded = m_connection &&
				m_connection->read_at(offset, buffer, size, received, error);
			g_netiso_statistics.remote_bytes.fetch_add(received, std::memory_order_relaxed);
			if (succeeded && received == size)
			{
				return true;
			}
			if (attempt || !reconnect_and_verify(error))
			{
				break;
			}
		}
		return false;
	}

	u64 read_at_locked(u64 offset, void* buffer, u64 requested)
	{
		if (!requested || offset >= m_identity.size)
		{
			return 0;
		}
		const u64 count = std::min(requested, m_identity.size - offset);
		if (!buffer)
		{
			fs::g_tls_error = fs::error::inval;
			return 0;
		}

		if (offset >= m_cache_offset && offset + count >= offset &&
			offset + count <= m_cache_offset + m_cache.size())
		{
			std::memcpy(buffer, m_cache.data() + (offset - m_cache_offset), count);
			g_netiso_statistics.logical_bytes.fetch_add(count, std::memory_order_relaxed);
			g_netiso_statistics.cached_bytes.fetch_add(count, std::memory_order_relaxed);
			g_netiso_statistics.cache_hits.fetch_add(1, std::memory_order_relaxed);
			return count;
		}

		std::string error;
		if (count <= read_ahead_size)
		{
			const u64 cache_offset = offset & ~(read_ahead_alignment - 1);
			const u64 cache_size = std::min(read_ahead_size, m_identity.size - cache_offset);
			std::vector<u8> cache(static_cast<usz>(cache_size));
			if (read_exact(cache_offset, cache.data(), cache.size(), error))
			{
				m_cache_offset = cache_offset;
				m_cache = std::move(cache);
				if (offset + count <= m_cache_offset + m_cache.size())
				{
					std::memcpy(buffer, m_cache.data() + (offset - m_cache_offset), count);
					g_netiso_statistics.logical_bytes.fetch_add(count, std::memory_order_relaxed);
					return count;
				}
			}
		}
		if (read_exact(offset, buffer, static_cast<usz>(count), error))
		{
			g_netiso_statistics.logical_bytes.fetch_add(count, std::memory_order_relaxed);
			return count;
		}

		set_fs_error(error);
		return 0;
	}

	netiso::endpoint m_server;
	std::string m_path;
	netiso::file_info m_identity;
	std::unique_ptr<netiso::connection> m_connection;
	std::mutex m_mutex;
	u64 m_position = 0;
	u64 m_cache_offset = 0;
	std::vector<u8> m_cache;
};

class netiso_dir final : public fs::dir_base
{
public:
	explicit netiso_dir(std::vector<netiso::directory_entry> entries)
		: m_entries(std::move(entries))
	{
	}

	bool read(fs::dir_entry& result) override
	{
		if (m_position >= m_entries.size())
		{
			return false;
		}
		const auto& source = m_entries[m_position++];
		static_cast<fs::stat_t&>(result) = to_fs_stat(source);
		result.name = source.name;
		return true;
	}

	void rewind() override
	{
		m_position = 0;
	}

private:
	std::vector<netiso::directory_entry> m_entries;
	usz m_position = 0;
};

std::string lower_copy(std::string value)
{
	std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character)
	{
		return static_cast<char>(std::tolower(character));
	});
	return value;
}

bool iso_filename(std::string_view name)
{
	const std::string lower = lower_copy(std::string{name});
	if (lower.ends_with(".iso"))
	{
		return true;
	}
	if (!lower.ends_with(".iso.0"))
	{
		return false;
	}
	return true;
}

std::string display_name(std::string name, bool strip_iso)
{
	if (strip_iso)
	{
		const std::string lower = lower_copy(name);
		if (lower.ends_with(".iso.0"))
		{
			name.resize(name.size() - 6);
		}
		else if (lower.ends_with(".iso"))
		{
			name.resize(name.size() - 4);
		}
	}
	for (char& character : name)
	{
		if (character == '_' || character == '.')
		{
			character = ' ';
		}
	}
	return name;
}

bool valid_title_id(std::string_view title_id)
{
	return !title_id.empty() && title_id.size() <= 32 &&
		std::all_of(title_id.begin(), title_id.end(), [](unsigned char character)
		{
			return std::isalnum(character) || character == '_' || character == '-';
		});
}
}

netiso_device::netiso_device(netiso::endpoint server)
	: m_server(std::move(server))
{
	fs_prefix = std::string{virtual_device_name};
}

const netiso::endpoint& netiso_device::server() const noexcept
{
	return m_server;
}

std::string netiso_device::virtual_path(const std::string& remote_path) const
{
	return fs_prefix + remote_path;
}

bool netiso_device::remote_path(
	const std::string& path, std::string& remote, std::string& error) const
{
	if (!path.starts_with(fs_prefix))
	{
		error = "NETISO virtual path has the wrong device prefix";
		return false;
	}
	remote = path.substr(fs_prefix.size());
	if (remote.empty())
	{
		remote = "/";
	}
	return netiso::valid_remote_path(remote, error);
}

void netiso_device::remember_error(std::string error) const
{
	std::lock_guard lock(m_error_mutex);
	m_last_error = std::move(error);
}

std::string netiso_device::last_error() const
{
	std::lock_guard lock(m_error_mutex);
	return m_last_error;
}

bool netiso_device::list_remote(const std::string& remote_path,
	std::vector<netiso::directory_entry>& entries, std::string& error) const
{
	netiso::connection connection{m_server};
	if (!connection.connect(error) || !connection.list_directory(remote_path, entries, error))
	{
		remember_error(error);
		return false;
	}
	return true;
}

bool netiso_device::stat(const std::string& path, fs::stat_t& info)
{
	info = {};
	std::string remote;
	std::string error;
	if (!remote_path(path, remote, error))
	{
		remember_error(error);
		set_fs_error(error);
		return false;
	}

	netiso::connection connection{m_server};
	netiso::file_info remote_info{};
	const bool virtual_iso = remote.starts_with(virtual_ps3_prefix);
	if (!connection.connect(error) ||
		!(virtual_iso ? connection.open_file(remote, remote_info, error)
			: connection.stat(remote, remote_info, error)))
	{
		remember_error(error);
		set_fs_error(error);
		return false;
	}
	info = to_fs_stat(remote_info);
	return true;
}

bool netiso_device::statfs(const std::string&, fs::device_stat& info)
{
	info.block_size = 4096;
	info.total_size = 0;
	info.total_free = 0;
	info.avail_free = 0;
	return true;
}

std::unique_ptr<fs::file_base> netiso_device::open(
	const std::string& path, bs_t<fs::open_mode> mode)
{
	if (mode & fs::write)
	{
		fs::g_tls_error = fs::error::readonly;
		return {};
	}
	std::string remote;
	std::string error;
	if (!remote_path(path, remote, error))
	{
		remember_error(error);
		set_fs_error(error);
		return {};
	}
	auto connection = std::make_unique<netiso::connection>(m_server);
	netiso::file_info identity{};
	if (!connection->connect(error) || !connection->open_file(remote, identity, error))
	{
		remember_error(error);
		set_fs_error(error);
		return {};
	}
	if (identity.is_directory)
	{
		fs::g_tls_error = fs::error::isdir;
		return {};
	}
	return std::make_unique<netiso_file>(m_server, std::move(remote), identity, std::move(connection));
}

std::unique_ptr<fs::dir_base> netiso_device::open_dir(const std::string& path)
{
	std::string remote;
	std::string error;
	if (!remote_path(path, remote, error))
	{
		remember_error(error);
		set_fs_error(error);
		return {};
	}
	std::vector<netiso::directory_entry> entries;
	if (!list_remote(remote, entries, error))
	{
		set_fs_error(error);
		return {};
	}
	return std::make_unique<netiso_dir>(std::move(entries));
}

std::vector<netiso_game_entry> enumerate_netiso_games(
	const netiso_device& device, std::string& error)
{
	std::vector<netiso_game_entry> games;
	std::unordered_set<std::string> seen;
	bool reached_server = false;
	std::string last_error;

	std::vector<netiso::directory_entry> entries;
	if (device.list_remote("/PS3ISO", entries, last_error))
	{
		reached_server = true;
		for (const auto& entry : entries)
		{
			if (entry.is_directory || !iso_filename(entry.name))
			{
				continue;
			}
			const std::string path = "/PS3ISO/" + entry.name;
			if (seen.emplace(path).second)
			{
				games.push_back({path, display_name(entry.name, true), netiso_game_kind::iso, entry.size});
			}
		}
	}

	entries.clear();
	if (device.list_remote("/GAMES", entries, last_error))
	{
		reached_server = true;
		for (const auto& entry : entries)
		{
			if (!entry.is_directory)
			{
				continue;
			}
			const std::string path = std::string{virtual_ps3_prefix} + "GAMES/" + entry.name;
			if (seen.emplace(path).second)
			{
				games.push_back({path, display_name(entry.name, false),
					netiso_game_kind::extracted_folder, 0});
			}
		}
	}

	if (!reached_server)
	{
		error = last_error.empty() ? "NETISO server exposes neither /PS3ISO nor /GAMES" : last_error;
		return {};
	}
	std::sort(games.begin(), games.end(), [](const auto& left, const auto& right)
	{
		return lower_copy(left.display_name) < lower_copy(right.display_name);
	});
	error.clear();
	return games;
}

bool inspect_netiso_game(
	const netiso_device& device,
	const std::string& remote_path,
	netiso_game_metadata& metadata,
	std::string& error)
{
	metadata = {};
	if (!(remote_path.starts_with("/PS3ISO/") ||
		remote_path.starts_with("/***PS3***/GAMES/")))
	{
		error = "Remote game path must be inside /PS3ISO or /GAMES";
		return false;
	}
	if (!netiso::valid_remote_path(remote_path, error))
	{
		return false;
	}

	const std::string path = device.virtual_path(remote_path);
	u64 size = 0;
	if (!is_iso_file(path, &size) || !size)
	{
		error = device.last_error();
		if (error.empty())
		{
			error = "Remote entry is not a readable PlayStation 3 ISO";
		}
		return false;
	}

	iso_archive archive{path};
	const psf::registry registry = archive.open_psf("PS3_GAME/PARAM.SFO");
	std::string title_id{psf::get_string(registry, "TITLE_ID")};
	std::string title{psf::get_string(registry, "TITLE")};
	const std::string category{psf::get_string(registry, "CATEGORY")};
	if (!valid_title_id(title_id) || category != "DG" ||
		!archive.is_file("PS3_GAME/USRDIR/EBOOT.BIN"))
	{
		error = "Remote entry is not a bootable PlayStation 3 game. Encrypted images require a matching server-side key";
		return false;
	}
	if (title.empty())
	{
		title = title_id;
	}
	metadata.virtual_path = path;
	metadata.title_id = std::move(title_id);
	metadata.title = std::move(title);
	metadata.size = size;
	return true;
}

netiso_statistics capture_netiso_statistics() noexcept
{
	return {
		g_netiso_statistics.remote_bytes.load(std::memory_order_relaxed),
		g_netiso_statistics.logical_bytes.load(std::memory_order_relaxed),
		g_netiso_statistics.cached_bytes.load(std::memory_order_relaxed),
		g_netiso_statistics.remote_reads.load(std::memory_order_relaxed),
		g_netiso_statistics.cache_hits.load(std::memory_order_relaxed),
		g_netiso_statistics.reconnects.load(std::memory_order_relaxed),
	};
}

void reset_netiso_statistics() noexcept
{
	g_netiso_statistics.remote_bytes.store(0, std::memory_order_relaxed);
	g_netiso_statistics.logical_bytes.store(0, std::memory_order_relaxed);
	g_netiso_statistics.cached_bytes.store(0, std::memory_order_relaxed);
	g_netiso_statistics.remote_reads.store(0, std::memory_order_relaxed);
	g_netiso_statistics.cache_hits.store(0, std::memory_order_relaxed);
	g_netiso_statistics.reconnects.store(0, std::memory_order_relaxed);
}
}
