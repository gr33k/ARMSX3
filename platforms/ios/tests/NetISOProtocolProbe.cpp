#include "NetISOProtocol.h"

#include <charconv>
#include <cstring>
#include <iostream>

int main(int argc, char** argv)
{
	if (argc < 2 || argc > 4)
	{
		std::cerr << "usage: netiso-probe HOST [PORT] [REMOTE_ISO_PATH]\n";
		return 2;
	}

	rpcs3::ios::netiso::endpoint endpoint{argv[1]};
	if (argc >= 3)
	{
		unsigned port = 0;
		const char* end = argv[2] + std::strlen(argv[2]);
		const auto result = std::from_chars(argv[2], end, port);
		if (result.ec != std::errc{} || result.ptr != end || !port || port > 65535)
		{
			std::cerr << "invalid port\n";
			return 2;
		}
		endpoint.port = static_cast<std::uint16_t>(port);
	}

	std::string error;
	rpcs3::ios::netiso::connection connection{endpoint};
	if (!connection.connect(error))
	{
		std::cerr << error << '\n';
		return 1;
	}

	std::vector<rpcs3::ios::netiso::directory_entry> iso_entries;
	if (!connection.list_directory("/PS3ISO", iso_entries, error))
	{
		std::cerr << error << '\n';
		return 1;
	}
	connection.close();

	rpcs3::ios::netiso::connection folders{endpoint};
	std::vector<rpcs3::ios::netiso::directory_entry> folder_entries;
	if (!folders.connect(error) || !folders.list_directory("/GAMES", folder_entries, error))
	{
		std::cerr << error << '\n';
		return 1;
	}
	std::cout << "PS3ISO entries=" << iso_entries.size()
		<< " GAMES entries=" << folder_entries.size() << '\n';

	if (argc < 4)
	{
		return 0;
	}

	rpcs3::ios::netiso::connection file{endpoint};
	rpcs3::ios::netiso::file_info info{};
	if (!file.connect(error) || !file.open_file(argv[3], info, error))
	{
		std::cerr << error << '\n';
		return 1;
	}
	char magic[5]{};
	std::size_t bytes_read = 0;
	if (!file.read_at(32769, magic, sizeof(magic), bytes_read, error) ||
		bytes_read != sizeof(magic) || std::memcmp(magic, "CD001", sizeof(magic)) != 0)
	{
		std::cerr << (error.empty() ? "remote image does not contain ISO magic" : error) << '\n';
		return 1;
	}
	std::cout << "random-read PASS size=" << info.size << " mtime=" << info.mtime << '\n';
	return 0;
}
