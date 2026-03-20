#pragma once

#ifdef _WIN32
#include <Windows.h>
#include <wrl/client.h>
#else
#include <WinAdapter.h>

namespace Microsoft::WRL {
template <typename T>
using ComPtr = CComPtr<T>;
}

#endif

#include <dxcapi.h>

#include <bit>
#include <cassert>
#include <cstdint>

#ifndef UNREACHABLE
#ifdef _MSC_VER
#define UNREACHABLE __assume(0)
#else
#define UNREACHABLE __builtin_unreachable()
#endif
#endif
#include <execution>
#include <filesystem>
#include <map>

#include <string>
#include <unordered_map>



#include <smolv.h>
#include <fmt/core.h>
#include <xxhash.h>
#include <zstd.h>



