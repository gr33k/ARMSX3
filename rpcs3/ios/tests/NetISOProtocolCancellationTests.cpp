#include "ios/NetISOProtocol.h"

#include <arpa/inet.h>
#include <chrono>
#include <cstring>
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>

namespace
{
bool check(bool condition, const char* message)
{
	if (!condition)
	{
		std::cerr << message << '\n';
	}
	return condition;
}
}

int main()
{
	const int listener = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	if (!check(listener >= 0, "unable to create loopback NETISO listener"))
	{
		return 1;
	}

	sockaddr_in address{};
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	if (!check(::bind(listener, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == 0,
		"unable to bind loopback NETISO listener") ||
		!check(::listen(listener, 1) == 0, "unable to listen for loopback NETISO client"))
	{
		::close(listener);
		return 1;
	}

	socklen_t address_size = sizeof(address);
	if (!check(::getsockname(listener, reinterpret_cast<sockaddr*>(&address), &address_size) == 0,
		"unable to read loopback NETISO port"))
	{
		::close(listener);
		return 1;
	}

	rpcs3::ios::netiso::connection connection({"127.0.0.1", ntohs(address.sin_port)});
	std::string connect_error;
	if (!check(connection.connect(connect_error), connect_error.c_str()))
	{
		::close(listener);
		return 1;
	}

	std::thread server([listener]
	{
		const int client = ::accept(listener, nullptr, nullptr);
		if (client >= 0)
		{
			char buffer[256];
			while (::recv(client, buffer, sizeof(buffer), 0) > 0)
			{
			}
			::close(client);
		}
		::close(listener);
	});

	bool opened = true;
	std::string open_error;
	const auto started = std::chrono::steady_clock::now();
	std::thread blocked_open([&]
	{
		rpcs3::ios::netiso::file_info info{};
		opened = connection.open_file("/***PS3***/GAMES/stalled", info, open_error);
	});

	std::this_thread::sleep_for(std::chrono::milliseconds(100));
	connection.cancel();
	blocked_open.join();
	server.join();
	const auto elapsed = std::chrono::steady_clock::now() - started;

	bool passed = true;
	passed &= check(!opened, "cancelled NETISO open unexpectedly succeeded");
	passed &= check(open_error == "NETISO operation cancelled",
		"cancelled NETISO open did not report cancellation");
	passed &= check(elapsed < std::chrono::seconds(2),
		"cancelled NETISO open waited for the socket timeout");

	rpcs3::ios::netiso::connection pre_cancelled({"127.0.0.1", ntohs(address.sin_port)});
	pre_cancelled.cancel();
	std::string pre_cancel_error;
	passed &= check(!pre_cancelled.connect(pre_cancel_error),
		"pre-cancelled NETISO connection unexpectedly connected");
	passed &= check(pre_cancel_error == "NETISO operation cancelled",
		"pre-cancelled NETISO connection did not fail closed");

	if (!passed)
	{
		return 1;
	}
	std::cout << "NETISO cancellation contract PASS\n";
	return 0;
}
