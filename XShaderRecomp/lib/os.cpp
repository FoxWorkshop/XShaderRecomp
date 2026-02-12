#include <filesystem>

#if defined(_WIN32)
#include <windows.h>
#elif defined(__linux__)
#include <unistd.h>
#include <limits.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#endif

std::filesystem::path GetUserDataDirectory()
{
#if defined(_WIN32)
    char* path = nullptr;
    size_t len = 0;
    _dupenv_s(&path, &len, "APPDATA");
    std::filesystem::path result(path);
    free(path);
    return result;

#elif defined(__linux__)
    const char* home = getenv("XDG_DATA_HOME");
    if (!home)
        home = getenv("HOME");

    return std::filesystem::path(home) / ".local/share";

#elif defined(__APPLE__)
    const char* home = getenv("HOME");
    return std::filesystem::path(home) / "Library/Application Support";
#endif
}
