#include "stdafx.h"
#include "unzip.h"

#include <zlib.h>

#include "util/serialization_ext.hpp"

std::vector<u8> unzip(const void* src, usz size)
{
	if (!src || !size) [[unlikely]]
	{
		return {};
	}

	std::vector<uchar> out(size * 6);

	z_stream zs{};
#ifndef _MSC_VER
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#endif
	int res = inflateInit2(&zs, 16 + 15);
	if (res != Z_OK)
	{
		return {};
	}
#ifndef _MSC_VER
#pragma GCC diagnostic pop
#endif
	zs.avail_in = static_cast<uInt>(size);
	zs.next_in = reinterpret_cast<const u8*>(src);
	zs.avail_out = static_cast<uInt>(out.size());
	zs.next_out  = out.data();

	while (zs.avail_in)
	{
		switch (inflate(&zs, Z_FINISH))
		{
		case Z_OK:
		case Z_STREAM_END:
			break;
		case Z_BUF_ERROR:
			if (zs.avail_in)
				break;
			[[fallthrough]];
		default:
			inflateEnd(&zs);
			return out;
		}

		if (zs.avail_in)
		{
			const auto cur_size = zs.next_out - out.data();
			out.resize(out.size() + 65536);
			zs.avail_out = static_cast<uInt>(out.size() - cur_size);
			zs.next_out = &out[cur_size];
		}
	}

	out.resize(zs.next_out - out.data());

	res = inflateEnd(&zs);

	return out;
}

bool unzip(const void* src, usz size, fs::file& out)
{
	if (!src || !size || !out)
	{
		return false;
	}

	bool is_valid = true;

	constexpr usz BUFSIZE = 32ULL * 1024ULL;
	std::vector<u8> tempbuf(BUFSIZE);
	z_stream strm{};
	strm.avail_in = ::narrow<uInt>(size);
	strm.avail_out = static_cast<uInt>(tempbuf.size());
	strm.next_in = reinterpret_cast<const u8*>(src);
	strm.next_out = tempbuf.data();
#ifndef _MSC_VER
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#endif
	int res = inflateInit(&strm);
	if (res != Z_OK)
	{
		return false;
	}
#ifndef _MSC_VER
#pragma GCC diagnostic pop
#endif
	while (strm.avail_in)
	{
		res = inflate(&strm, Z_NO_FLUSH);
		if (res == Z_STREAM_END)
			break;
		if (res != Z_OK)
			is_valid = false;

		if (strm.avail_out)
			break;

		if (out.write(tempbuf.data(), tempbuf.size()) != tempbuf.size())
		{
			is_valid = false;
		}

		strm.next_out = tempbuf.data();
		strm.avail_out = static_cast<uInt>(tempbuf.size());
	}

	res = inflate(&strm, Z_FINISH);

	if (res != Z_STREAM_END)
		is_valid = false;

	if (strm.avail_out < tempbuf.size())
	{
		const usz bytes_to_write = tempbuf.size() - strm.avail_out;

		if (out.write(tempbuf.data(), bytes_to_write) != bytes_to_write)
		{
			is_valid = false;
		}
	}

	res = inflateEnd(&strm);

	return is_valid;
}

bool unzip(const fs::file& src, u64 offset, fs::file& out)
{
	if (!src || !out || offset >= src.size())
	{
		return false;
	}

	return unzip(src, offset, src.size() - offset, umax, out);
}

bool unzip(const fs::file& src, u64 offset, u64 compressed_size, u64 expected_size, fs::file& out)
{
	if (!src || !out || !compressed_size || offset > src.size() || compressed_size > src.size() - offset)
	{
		return false;
	}

	constexpr usz buffer_size = 64 * 1024;
	std::vector<u8> input(buffer_size);
	std::vector<u8> output(buffer_size);
	z_stream stream{};
#ifndef _MSC_VER
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#endif
	if (inflateInit(&stream) != Z_OK)
	{
		return false;
	}
#ifndef _MSC_VER
#pragma GCC diagnostic pop
#endif

	bool complete = false;
	u64 read_offset = offset;
	const u64 read_end = offset + compressed_size;
	while (!complete && read_offset < read_end)
	{
		const usz requested = static_cast<usz>(std::min<u64>(input.size(), read_end - read_offset));
		const usz read = src.read_at(read_offset, input.data(), requested);
		if (!read)
		{
			break;
		}
		read_offset += read;
		stream.next_in = input.data();
		stream.avail_in = ::narrow<uInt>(read);

		do
		{
			stream.next_out = output.data();
			stream.avail_out = ::narrow<uInt>(output.size());
			const int result = inflate(&stream, Z_NO_FLUSH);
			if (result != Z_OK && result != Z_STREAM_END)
			{
				inflateEnd(&stream);
				return false;
			}

			const usz produced = output.size() - stream.avail_out;
			if (expected_size != umax && stream.total_out > expected_size)
			{
				inflateEnd(&stream);
				return false;
			}
			if (produced && out.write(output.data(), produced) != produced)
			{
				inflateEnd(&stream);
				return false;
			}
			complete = result == Z_STREAM_END;
		}
		while (!complete && (stream.avail_in || stream.avail_out == 0));
	}

	const u64 consumed = stream.total_in;
	const u64 produced = stream.total_out;
	inflateEnd(&stream);
	return complete && consumed == compressed_size &&
		(expected_size == umax || produced == expected_size);
}

bool zip(const void* src, usz size, fs::file& out, bool multi_thread_it)
{
	if (!src || !size || !out)
	{
		return false;
	}

	utils::serial compressor;
	compressor.set_expect_little_data(!multi_thread_it || size < 0x40'0000);
	compressor.m_file_handler = make_compressed_serialization_file_handler(out);

	std::string_view buffer_view{static_cast<const char*>(src), size};

	while (!buffer_view.empty())
	{
		if (!compressor.m_file_handler->is_valid())
		{
			return false;
		}

		const std::string_view slice = buffer_view.substr(0, 0x50'0000);

		compressor(slice);
		compressor.breathe();
		buffer_view = buffer_view.substr(slice.size());
	}

	compressor.m_file_handler->finalize(compressor);

	if (!compressor.m_file_handler->is_valid())
	{
		return false;
	}

	return true;
}
