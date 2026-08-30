#pragma once

#include "Utilities/File.h"
#include "util/types.hpp"

#include <vector>

std::vector<u8> unzip(const void* src, usz size);

template <typename T>
inline std::vector<u8> unzip(const T& src)
{
	return unzip(src.data(), src.size());
}

bool unzip(const void* src, usz size, fs::file& out);

// Inflate a zlib stream directly from a file range without first duplicating
// the complete compressed payload in memory.
bool unzip(const fs::file& src, u64 offset, fs::file& out);

// Inflate exactly one bounded zlib stream and verify its expected output size.
// This is used for SELF segment tables where another compressed stream may
// immediately follow the current segment in the same file.
bool unzip(const fs::file& src, u64 offset, u64 compressed_size, u64 expected_size, fs::file& out);

template <typename T>
inline bool unzip(const std::vector<u8>& src, fs::file& out)
{
	return unzip(src.data(), src.size(), out);
}

bool zip(const void* src, usz size, fs::file& out, bool multi_thread_it = false);

template <typename T>
inline bool zip(const T& src, fs::file& out)
{
	return zip(src.data(), src.size(), out);
}
