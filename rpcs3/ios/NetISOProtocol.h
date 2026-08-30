#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace rpcs3::ios::netiso
{
constexpr std::uint16_t default_port = 38008;

struct endpoint
{
	std::string host;
	std::uint16_t port = default_port;
};

struct file_info
{
	std::uint64_t size = 0;
	std::uint64_t mtime = 0;
	std::uint64_t ctime = 0;
	std::uint64_t atime = 0;
	bool is_directory = false;
};

struct directory_entry : file_info
{
	std::string name;
};

class connection final
{
public:
	explicit connection(endpoint server);
	~connection();

	connection(const connection&) = delete;
	connection& operator=(const connection&) = delete;

	bool connect(std::string& error);
	void close() noexcept;
	bool is_connected() const noexcept;

	bool stat(const std::string& path, file_info& info, std::string& error);
	bool open_file(const std::string& path, file_info& info, std::string& error);
	bool read_at(std::uint64_t offset, void* buffer, std::size_t size,
		std::size_t& bytes_read, std::string& error);
	bool list_directory(const std::string& path,
		std::vector<directory_entry>& entries, std::string& error);

private:
	bool send_all(const void* data, std::size_t size, std::string& error);
	bool receive_all(void* data, std::size_t size, std::string& error);
	bool send_path_command(std::uint16_t opcode, const std::string& path,
		std::string& error);

	endpoint m_server;
	int m_socket = -1;
};

bool valid_remote_path(const std::string& path, std::string& error);
}
