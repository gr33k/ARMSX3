#include "NetISOProtocol.h"

#include <algorithm>
#include <array>
#include <bit>
#include <cerrno>
#include <cstring>
#include <limits>
#include <netdb.h>
#include <poll.h>
#include <string_view>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/tcp.h>
#include <unistd.h>
#include <fcntl.h>
#include <utility>

namespace rpcs3::ios::netiso
{
namespace
{
constexpr std::uint16_t command_open_file = 0x1224;
constexpr std::uint16_t command_read_file = 0x1227;
constexpr std::uint16_t command_open_dir = 0x122a;
constexpr std::uint16_t command_stat_file = 0x1230;
constexpr std::uint16_t command_read_dir = 0x1232;
constexpr std::size_t command_size = 16;
constexpr std::size_t maximum_remote_path = 4096;
constexpr std::size_t maximum_read_size = 4 * 1024 * 1024;
constexpr std::uint64_t maximum_directory_entries = 4096;
constexpr int connect_timeout_ms = 5000;
constexpr int io_timeout_seconds = 15;

#pragma pack(push, 1)
struct path_command
{
	std::uint16_t opcode;
	std::uint16_t path_length;
	std::uint8_t padding[12];
};

struct plain_command
{
	std::uint16_t opcode;
	std::uint8_t padding[14];
};

struct open_result
{
	std::uint64_t file_size;
	std::uint64_t mtime;
};

struct stat_result
{
	std::uint64_t file_size;
	std::uint64_t mtime;
	std::uint64_t ctime;
	std::uint64_t atime;
	std::int8_t is_directory;
};

struct read_command
{
	std::uint16_t opcode;
	std::uint16_t padding;
	std::uint32_t byte_count;
	std::uint64_t offset;
};

struct read_result
{
	std::uint32_t bytes_read;
};

struct directory_result
{
	std::uint64_t entry_count;
};

struct directory_result_entry
{
	std::uint64_t file_size;
	std::uint64_t mtime;
	std::int8_t is_directory;
	char name[512];
};
#pragma pack(pop)

static_assert(sizeof(path_command) == command_size);
static_assert(sizeof(plain_command) == command_size);
static_assert(sizeof(open_result) == 16);
static_assert(sizeof(stat_result) == 33);
static_assert(sizeof(read_command) == command_size);
static_assert(sizeof(read_result) == 4);
static_assert(sizeof(directory_result_entry) == 529);

template <typename T>
constexpr T byte_swap(T value)
{
	if constexpr (sizeof(T) == sizeof(std::uint16_t))
	{
		return static_cast<T>(__builtin_bswap16(static_cast<std::uint16_t>(value)));
	}
	else if constexpr (sizeof(T) == sizeof(std::uint32_t))
	{
		return static_cast<T>(__builtin_bswap32(static_cast<std::uint32_t>(value)));
	}
	else
	{
		return static_cast<T>(__builtin_bswap64(static_cast<std::uint64_t>(value)));
	}
}

template <typename T>
constexpr T big_endian(T value)
{
	if constexpr (std::endian::native == std::endian::little)
	{
		return byte_swap(value);
	}
	return value;
}

std::string socket_error(const char* operation)
{
	return std::string{operation} + ": " + std::strerror(errno);
}

std::string socket_error(const char* operation, int error_number)
{
	return std::string{operation} + ": " + std::strerror(error_number);
}

bool valid_entry_name(std::string_view name)
{
	return !name.empty() && name != "." && name != ".." &&
		name.find('/') == std::string_view::npos &&
		name.find('\\') == std::string_view::npos &&
		name.find('\0') == std::string_view::npos;
}
}

connection::connection(endpoint server)
	: m_server(std::move(server))
{
}

connection::~connection()
{
	close();
}

bool connection::connect(std::string& error)
{
	close();
	if (m_cancelled.load(std::memory_order_acquire))
	{
		error = "NETISO operation cancelled";
		return false;
	}
	if (m_server.host.empty() || !m_server.port)
	{
		error = "NETISO host and port are required";
		return false;
	}

	addrinfo hints{};
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_protocol = IPPROTO_TCP;
	const std::string service = std::to_string(m_server.port);
	addrinfo* addresses = nullptr;
	const int lookup = ::getaddrinfo(m_server.host.c_str(), service.c_str(), &hints, &addresses);
	if (lookup != 0)
	{
		error = std::string{"NETISO address lookup failed: "} + gai_strerror(lookup);
		return false;
	}

	int last_error = 0;
	for (addrinfo* address = addresses; address; address = address->ai_next)
	{
		if (m_cancelled.load(std::memory_order_acquire))
		{
			last_error = ECANCELED;
			break;
		}
		const int candidate = ::socket(address->ai_family, address->ai_socktype, address->ai_protocol);
		if (candidate < 0)
		{
			last_error = errno;
			continue;
		}

#if defined(SO_NOSIGPIPE)
		const int no_sigpipe = 1;
		::setsockopt(candidate, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
#endif
		const int no_delay = 1;
		::setsockopt(candidate, IPPROTO_TCP, TCP_NODELAY, &no_delay, sizeof(no_delay));
		const int original_flags = ::fcntl(candidate, F_GETFL, 0);
		if (original_flags < 0 || ::fcntl(candidate, F_SETFL, original_flags | O_NONBLOCK) != 0)
		{
			last_error = errno;
			::close(candidate);
			continue;
		}

		int result = ::connect(candidate, address->ai_addr, address->ai_addrlen);
		int connect_error = result == 0 ? 0 : errno;
		if (result != 0 && connect_error == EINPROGRESS)
		{
			pollfd descriptor{candidate, POLLOUT, 0};
			do
			{
				result = ::poll(&descriptor, 1, connect_timeout_ms);
			}
			while (result < 0 && errno == EINTR);
			if (result > 0)
			{
				int pending_error = 0;
				socklen_t pending_size = sizeof(pending_error);
				if (::getsockopt(candidate, SOL_SOCKET, SO_ERROR, &pending_error, &pending_size) != 0)
				{
					connect_error = errno;
					result = -1;
				}
				else if (pending_error)
				{
					connect_error = pending_error;
					result = -1;
				}
				else if (!(descriptor.revents & POLLOUT) ||
					(descriptor.revents & (POLLERR | POLLHUP | POLLNVAL)))
				{
					connect_error = EIO;
					result = -1;
				}
				else
				{
					connect_error = 0;
					result = 0;
				}
			}
			else if (result == 0)
			{
				connect_error = ETIMEDOUT;
				result = -1;
			}
			else
			{
				connect_error = errno;
			}
		}

		if (result == 0)
		{
			if (::fcntl(candidate, F_SETFL, original_flags) == 0)
			{
				if (!m_cancelled.load(std::memory_order_acquire))
				{
					timeval timeout{io_timeout_seconds, 0};
					::setsockopt(candidate, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
					::setsockopt(candidate, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
					{
						std::lock_guard lock(m_socket_mutex);
						if (!m_cancelled.load(std::memory_order_relaxed))
						{
							m_socket = candidate;
							break;
						}
					}
				}
				connect_error = ECANCELED;
			}
			else
			{
				connect_error = errno;
			}
		}
		last_error = connect_error;
		::close(candidate);
	}
	::freeaddrinfo(addresses);

	if (m_socket < 0)
	{
		if (m_cancelled.load(std::memory_order_acquire))
		{
			error = "NETISO operation cancelled";
			return false;
		}
		error = socket_error("NETISO connection failed", last_error ? last_error : ECONNREFUSED);
		return false;
	}
	return true;
}

void connection::cancel() noexcept
{
	m_cancelled.store(true, std::memory_order_release);
	std::lock_guard lock(m_socket_mutex);
	if (m_socket >= 0)
	{
		// shutdown wakes a blocked send/receive without racing descriptor reuse;
		// the operation that owns the connection performs the final close.
		::shutdown(m_socket, SHUT_RDWR);
	}
}

void connection::close() noexcept
{
	int descriptor = -1;
	{
		std::lock_guard lock(m_socket_mutex);
		descriptor = std::exchange(m_socket, -1);
	}
	if (descriptor >= 0)
	{
		::close(descriptor);
	}
}

bool connection::is_connected() const noexcept
{
	return socket_handle() >= 0 && !m_cancelled.load(std::memory_order_acquire);
}

int connection::socket_handle() const noexcept
{
	std::lock_guard lock(m_socket_mutex);
	return m_socket;
}

bool connection::send_all(const void* data, std::size_t size, std::string& error)
{
	const auto* bytes = static_cast<const std::uint8_t*>(data);
	while (size)
	{
		if (m_cancelled.load(std::memory_order_acquire))
		{
			error = "NETISO operation cancelled";
			close();
			return false;
		}
		const int descriptor = socket_handle();
		if (descriptor < 0)
		{
			error = "NETISO connection is closed";
			return false;
		}
#if defined(MSG_NOSIGNAL)
		const ssize_t sent = ::send(descriptor, bytes, size, MSG_NOSIGNAL);
#else
		const ssize_t sent = ::send(descriptor, bytes, size, 0);
#endif
		if (sent < 0 && errno == EINTR)
		{
			continue;
		}
		if (sent <= 0)
		{
			error = m_cancelled.load(std::memory_order_acquire)
				? "NETISO operation cancelled"
				: socket_error("NETISO send failed");
			close();
			return false;
		}
		bytes += sent;
		size -= static_cast<std::size_t>(sent);
	}
	return true;
}

bool connection::receive_all(void* data, std::size_t size, std::string& error)
{
	auto* bytes = static_cast<std::uint8_t*>(data);
	while (size)
	{
		if (m_cancelled.load(std::memory_order_acquire))
		{
			error = "NETISO operation cancelled";
			close();
			return false;
		}
		const int descriptor = socket_handle();
		if (descriptor < 0)
		{
			error = "NETISO connection is closed";
			return false;
		}
		const ssize_t received = ::recv(descriptor, bytes, size, 0);
		if (received < 0 && errno == EINTR)
		{
			continue;
		}
		if (received <= 0)
		{
			error = m_cancelled.load(std::memory_order_acquire)
				? "NETISO operation cancelled"
				: received == 0 ? "NETISO server closed the connection" : socket_error("NETISO receive failed");
			close();
			return false;
		}
		bytes += received;
		size -= static_cast<std::size_t>(received);
	}
	return true;
}

bool connection::send_path_command(std::uint16_t opcode, const std::string& path, std::string& error)
{
	if (!valid_remote_path(path, error))
	{
		return false;
	}
	path_command command{};
	command.opcode = big_endian(opcode);
	command.path_length = big_endian(static_cast<std::uint16_t>(path.size()));
	return send_all(&command, sizeof(command), error) && send_all(path.data(), path.size(), error);
}

bool connection::stat(const std::string& path, file_info& info, std::string& error)
{
	info = {};
	if (!is_connected() && !connect(error))
	{
		return false;
	}
	if (!send_path_command(command_stat_file, path, error))
	{
		return false;
	}
	stat_result result{};
	if (!receive_all(&result, sizeof(result), error))
	{
		return false;
	}
	const std::uint64_t size = big_endian(result.file_size);
	if (size == std::numeric_limits<std::uint64_t>::max())
	{
		error = "NETISO path was not found: " + path;
		return false;
	}
	info.size = size;
	info.mtime = big_endian(result.mtime);
	info.ctime = big_endian(result.ctime);
	info.atime = big_endian(result.atime);
	info.is_directory = result.is_directory != 0;
	return true;
}

bool connection::open_file(const std::string& path, file_info& info, std::string& error)
{
	info = {};
	if (!is_connected() && !connect(error))
	{
		return false;
	}
	if (!send_path_command(command_open_file, path, error))
	{
		return false;
	}
	open_result result{};
	if (!receive_all(&result, sizeof(result), error))
	{
		return false;
	}
	const std::uint64_t size = big_endian(result.file_size);
	if (size == std::numeric_limits<std::uint64_t>::max())
	{
		error = "NETISO file could not be opened: " + path;
		return false;
	}
	info.size = size;
	info.mtime = big_endian(result.mtime);
	return true;
}

bool connection::read_at(std::uint64_t offset, void* buffer, std::size_t size,
	std::size_t& bytes_read, std::string& error)
{
	bytes_read = 0;
	if (!is_connected())
	{
		error = "NETISO file connection is not open";
		return false;
	}
	if (!buffer && size)
	{
		error = "NETISO read buffer is null";
		return false;
	}
	while (size)
	{
		const std::size_t request = std::min(size, maximum_read_size);
		read_command command{};
		command.opcode = big_endian(command_read_file);
		command.byte_count = big_endian(static_cast<std::uint32_t>(request));
		command.offset = big_endian(offset);
		if (!send_all(&command, sizeof(command), error))
		{
			return false;
		}
		read_result result{};
		if (!receive_all(&result, sizeof(result), error))
		{
			return false;
		}
		const std::int32_t received = static_cast<std::int32_t>(big_endian(result.bytes_read));
		if (received < 0 || static_cast<std::size_t>(received) > request)
		{
			error = "NETISO server returned an invalid read length (received=" +
				std::to_string(received) + ", requested=" + std::to_string(request) + ")";
			return false;
		}
		if (received && !receive_all(buffer, static_cast<std::size_t>(received), error))
		{
			return false;
		}
		bytes_read += static_cast<std::size_t>(received);
		if (static_cast<std::size_t>(received) != request)
		{
			break;
		}
		offset += request;
		buffer = static_cast<std::uint8_t*>(buffer) + request;
		size -= request;
	}
	return true;
}

bool connection::list_directory(const std::string& path,
	std::vector<directory_entry>& entries, std::string& error)
{
	entries.clear();
	if (!is_connected() && !connect(error))
	{
		return false;
	}
	if (!send_path_command(command_open_dir, path, error))
	{
		return false;
	}
	std::uint32_t open_status = 0;
	if (!receive_all(&open_status, sizeof(open_status), error))
	{
		return false;
	}
	if (static_cast<std::int32_t>(big_endian(open_status)) != 0)
	{
		error = "NETISO directory was not found: " + path;
		return false;
	}

	plain_command command{};
	command.opcode = big_endian(command_read_dir);
	if (!send_all(&command, sizeof(command), error))
	{
		return false;
	}
	directory_result result{};
	if (!receive_all(&result, sizeof(result), error))
	{
		return false;
	}
	const std::uint64_t count = big_endian(result.entry_count);
	if (count > maximum_directory_entries)
	{
		error = "NETISO directory response exceeded the 4096-entry safety limit";
		return false;
	}

	entries.reserve(static_cast<std::size_t>(count));
	for (std::uint64_t index = 0; index < count; index++)
	{
		directory_result_entry wire{};
		if (!receive_all(&wire, sizeof(wire), error))
		{
			entries.clear();
			return false;
		}
		const std::size_t name_size = strnlen(wire.name, sizeof(wire.name));
		if (name_size == sizeof(wire.name))
		{
			error = "NETISO directory entry was not terminated";
			entries.clear();
			return false;
		}
		std::string name{wire.name, name_size};
		if (!valid_entry_name(name))
		{
			error = "NETISO directory contained an unsafe entry name";
			entries.clear();
			return false;
		}
		directory_entry entry{};
		entry.name = std::move(name);
		entry.size = big_endian(wire.file_size);
		entry.mtime = big_endian(wire.mtime);
		entry.is_directory = wire.is_directory != 0;
		entries.emplace_back(std::move(entry));
	}
	return true;
}

bool valid_remote_path(const std::string& path, std::string& error)
{
	if (path.empty() || path.front() != '/')
	{
		error = "NETISO paths must be absolute";
		return false;
	}
	if (path.size() > maximum_remote_path || path.size() > std::numeric_limits<std::uint16_t>::max())
	{
		error = "NETISO path exceeds the supported length";
		return false;
	}
	if (path.find('\0') != std::string::npos || path == "/.." || path.ends_with("/..") ||
		path.find("/../") != std::string::npos)
	{
		error = "NETISO path contains an unsafe component";
		return false;
	}
	return true;
}
}
