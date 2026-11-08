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
#include <cstdio>

// define XSHADER_RECOMP_NOLOGGING to stub logging
#ifdef XSHADER_RECOMP_NOLOGGING
#define XSHR_LOG(...) ((void)0)
#else
#define XSHR_LOG(...) printf(__VA_ARGS__)
#endif

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
