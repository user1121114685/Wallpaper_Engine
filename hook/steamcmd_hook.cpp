#include <windows.h>
#include <shellapi.h>
#include <detours.h>

#include <algorithm>
#include <cstdint>
#include <cwchar>
#include <cwctype>
#include <process.h>

#pragma comment(lib, "Shell32.lib")
#include <mutex>
#include <string>
#include <vector>

namespace {
constexpr GUID kConfigId = {0x2b715b62, 0xe190, 0x4b71,
                            {0x90, 0x17, 0x53, 0xb8, 0x8d, 0x96, 0x37, 0x12}};
constexpr ULONG kConfigVersion = 2;
constexpr DWORD kBufferSize = 1024 * 1024;

struct HookConfig {
  ULONG version;
  HANDLE output;
  HANDLE input;
  wchar_t steamDirectory[MAX_PATH];
  wchar_t workshopDirectory[MAX_PATH];
};

HMODULE g_module = nullptr;
HookConfig g_session{};
bool g_isInjectedProcess = false;
bool g_hookReady = false;
HANDLE g_outputRead = INVALID_HANDLE_VALUE;
HANDLE g_outputWrite = INVALID_HANDLE_VALUE;
HANDLE g_inputRead = INVALID_HANDLE_VALUE;
HANDLE g_inputWrite = INVALID_HANDLE_VALUE;
HANDLE g_job = nullptr;
HANDLE g_process = nullptr;
char g_dllPathAnsi[MAX_PATH]{};
std::mutex g_sessionMutex;

using WriteConsoleWFn = BOOL(WINAPI*)(HANDLE, const VOID*, DWORD, LPDWORD, LPVOID);
using WriteConsoleAFn = BOOL(WINAPI*)(HANDLE, const VOID*, DWORD, LPDWORD, LPVOID);
using WriteFileFn = BOOL(WINAPI*)(HANDLE, LPCVOID, DWORD, LPDWORD, LPOVERLAPPED);
using ReadFileFn = BOOL(WINAPI*)(HANDLE, LPVOID, DWORD, LPDWORD, LPOVERLAPPED);
using CreateFileWFn = HANDLE(WINAPI*)(LPCWSTR, DWORD, DWORD,
    LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
using CreateFileAFn = HANDLE(WINAPI*)(LPCSTR, DWORD, DWORD,
    LPSECURITY_ATTRIBUTES, DWORD, DWORD, HANDLE);
using CreateDirectoryWFn = BOOL(WINAPI*)(LPCWSTR, LPSECURITY_ATTRIBUTES);
using CreateDirectoryAFn = BOOL(WINAPI*)(LPCSTR, LPSECURITY_ATTRIBUTES);
using GetFileAttributesWFn = DWORD(WINAPI*)(LPCWSTR);
using GetFileAttributesAFn = DWORD(WINAPI*)(LPCSTR);
using GetFileAttributesExWFn = BOOL(WINAPI*)(LPCWSTR, GET_FILEEX_INFO_LEVELS,
    LPVOID);
using GetFileAttributesExAFn = BOOL(WINAPI*)(LPCSTR, GET_FILEEX_INFO_LEVELS,
    LPVOID);
using FindFirstFileWFn = HANDLE(WINAPI*)(LPCWSTR, LPWIN32_FIND_DATAW);
using FindFirstFileAFn = HANDLE(WINAPI*)(LPCSTR, LPWIN32_FIND_DATAA);
using DeleteFileWFn = BOOL(WINAPI*)(LPCWSTR);
using DeleteFileAFn = BOOL(WINAPI*)(LPCSTR);
using RemoveDirectoryWFn = BOOL(WINAPI*)(LPCWSTR);
using RemoveDirectoryAFn = BOOL(WINAPI*)(LPCSTR);
using MoveFileWFn = BOOL(WINAPI*)(LPCWSTR, LPCWSTR);
using MoveFileAFn = BOOL(WINAPI*)(LPCSTR, LPCSTR);
using MoveFileExWFn = BOOL(WINAPI*)(LPCWSTR, LPCWSTR, DWORD);
using MoveFileExAFn = BOOL(WINAPI*)(LPCSTR, LPCSTR, DWORD);
using CopyFileWFn = BOOL(WINAPI*)(LPCWSTR, LPCWSTR, BOOL);
using CopyFileAFn = BOOL(WINAPI*)(LPCSTR, LPCSTR, BOOL);
using SetFileAttributesWFn = BOOL(WINAPI*)(LPCWSTR, DWORD);
using SetFileAttributesAFn = BOOL(WINAPI*)(LPCSTR, DWORD);
using CreateProcessWFn = BOOL(WINAPI*)(LPCWSTR, LPWSTR, LPSECURITY_ATTRIBUTES,
    LPSECURITY_ATTRIBUTES, BOOL, DWORD, LPVOID, LPCWSTR,
    LPSTARTUPINFOW, LPPROCESS_INFORMATION);
using CreateProcessAFn = BOOL(WINAPI*)(LPCSTR, LPSTR, LPSECURITY_ATTRIBUTES,
    LPSECURITY_ATTRIBUTES, BOOL, DWORD, LPVOID, LPCSTR,
    LPSTARTUPINFOA, LPPROCESS_INFORMATION);

WriteConsoleWFn g_realWriteConsoleW = WriteConsoleW;
WriteConsoleAFn g_realWriteConsoleA = WriteConsoleA;
WriteFileFn g_realWriteFile = WriteFile;
ReadFileFn g_realReadFile = ReadFile;
CreateFileWFn g_realCreateFileW = CreateFileW;
CreateFileAFn g_realCreateFileA = CreateFileA;
CreateDirectoryWFn g_realCreateDirectoryW = CreateDirectoryW;
CreateDirectoryAFn g_realCreateDirectoryA = CreateDirectoryA;
GetFileAttributesWFn g_realGetFileAttributesW = GetFileAttributesW;
GetFileAttributesAFn g_realGetFileAttributesA = GetFileAttributesA;
GetFileAttributesExWFn g_realGetFileAttributesExW = GetFileAttributesExW;
GetFileAttributesExAFn g_realGetFileAttributesExA = GetFileAttributesExA;
FindFirstFileWFn g_realFindFirstFileW = FindFirstFileW;
FindFirstFileAFn g_realFindFirstFileA = FindFirstFileA;
DeleteFileWFn g_realDeleteFileW = DeleteFileW;
DeleteFileAFn g_realDeleteFileA = DeleteFileA;
RemoveDirectoryWFn g_realRemoveDirectoryW = RemoveDirectoryW;
RemoveDirectoryAFn g_realRemoveDirectoryA = RemoveDirectoryA;
MoveFileWFn g_realMoveFileW = MoveFileW;
MoveFileAFn g_realMoveFileA = MoveFileA;
MoveFileExWFn g_realMoveFileExW = MoveFileExW;
MoveFileExAFn g_realMoveFileExA = MoveFileExA;
CopyFileWFn g_realCopyFileW = CopyFileW;
CopyFileAFn g_realCopyFileA = CopyFileA;
SetFileAttributesWFn g_realSetFileAttributesW = SetFileAttributesW;
SetFileAttributesAFn g_realSetFileAttributesA = SetFileAttributesA;
CreateProcessWFn g_realCreateProcessW = CreateProcessW;
CreateProcessAFn g_realCreateProcessA = CreateProcessA;

std::wstring RedirectWorkshopPath(LPCWSTR path) {
  if (!path || !*path || !g_isInjectedProcess || !g_hookReady ||
      !g_session.workshopDirectory[0]) {
    return {};
  }

  const DWORD previousError = GetLastError();
  std::wstring redirected;
  std::vector<wchar_t> fullPath(32768);
  const DWORD length = GetFullPathNameW(path,
      static_cast<DWORD>(fullPath.size()), fullPath.data(), nullptr);
  if (length > 0 && length < fullPath.size()) {
    std::wstring actual(fullPath.data(), length);
    std::wstring workshopRoot(g_session.steamDirectory);
    workshopRoot.append(L"\\steamapps\\workshop\\content\\431960");
    for (wchar_t& character : actual) {
      if (character == L'/') character = L'\\';
    }
    for (wchar_t& character : workshopRoot) {
      if (character == L'/') character = L'\\';
    }
    while (workshopRoot.size() > 3 && workshopRoot.back() == L'\\') {
      workshopRoot.pop_back();
    }

    const size_t rootLength = workshopRoot.size();
    if (_wcsnicmp(actual.c_str(), workshopRoot.c_str(), rootLength) == 0 &&
        (actual.size() == rootLength || actual[rootLength] == L'\\')) {
      redirected.assign(g_session.workshopDirectory);
      redirected.append(actual.substr(rootLength));
    }
  }
  SetLastError(previousError);
  return redirected;
}

std::wstring WideFromAnsi(LPCSTR path) {
  if (!path || !*path) return {};
  const int length = MultiByteToWideChar(CP_ACP, 0, path, -1, nullptr, 0);
  if (length <= 1) return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_ACP, 0, path, -1, result.data(), length);
  result.resize(static_cast<size_t>(length - 1));
  return result;
}

std::string AnsiFromWide(const std::wstring& path) {
  if (path.empty()) return {};
  const int length = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS,
      path.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (length <= 1) return {};
  std::string result(static_cast<size_t>(length), '\0');
  if (!WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, path.c_str(), -1,
          result.data(), length, nullptr, nullptr)) {
    return {};
  }
  result.resize(static_cast<size_t>(length - 1));
  return result;
}

std::string RedirectWorkshopPathA(LPCSTR path) {
  return AnsiFromWide(RedirectWorkshopPath(WideFromAnsi(path).c_str()));
}

HANDLE WINAPI HookCreateFileW(LPCWSTR path, DWORD access, DWORD sharing,
    LPSECURITY_ATTRIBUTES security, DWORD creation, DWORD flags,
    HANDLE templateFile) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realCreateFileW(redirected.empty() ? path : redirected.c_str(),
      access, sharing, security, creation, flags, templateFile);
}

HANDLE WINAPI HookCreateFileA(LPCSTR path, DWORD access, DWORD sharing,
    LPSECURITY_ATTRIBUTES security, DWORD creation, DWORD flags,
    HANDLE templateFile) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realCreateFileA(redirected.empty() ? path : redirected.c_str(),
      access, sharing, security, creation, flags, templateFile);
}

BOOL WINAPI HookCreateDirectoryW(LPCWSTR path,
    LPSECURITY_ATTRIBUTES security) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realCreateDirectoryW(redirected.empty() ? path : redirected.c_str(),
      security);
}

BOOL WINAPI HookCreateDirectoryA(LPCSTR path,
    LPSECURITY_ATTRIBUTES security) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realCreateDirectoryA(redirected.empty() ? path : redirected.c_str(),
      security);
}

DWORD WINAPI HookGetFileAttributesW(LPCWSTR path) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realGetFileAttributesW(redirected.empty() ? path : redirected.c_str());
}

DWORD WINAPI HookGetFileAttributesA(LPCSTR path) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realGetFileAttributesA(redirected.empty() ? path : redirected.c_str());
}

BOOL WINAPI HookGetFileAttributesExW(LPCWSTR path,
    GET_FILEEX_INFO_LEVELS level, LPVOID information) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realGetFileAttributesExW(
      redirected.empty() ? path : redirected.c_str(), level, information);
}

BOOL WINAPI HookGetFileAttributesExA(LPCSTR path,
    GET_FILEEX_INFO_LEVELS level, LPVOID information) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realGetFileAttributesExA(
      redirected.empty() ? path : redirected.c_str(), level, information);
}

HANDLE WINAPI HookFindFirstFileW(LPCWSTR path, LPWIN32_FIND_DATAW data) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realFindFirstFileW(redirected.empty() ? path : redirected.c_str(), data);
}

HANDLE WINAPI HookFindFirstFileA(LPCSTR path, LPWIN32_FIND_DATAA data) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realFindFirstFileA(redirected.empty() ? path : redirected.c_str(), data);
}

BOOL WINAPI HookDeleteFileW(LPCWSTR path) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realDeleteFileW(redirected.empty() ? path : redirected.c_str());
}

BOOL WINAPI HookDeleteFileA(LPCSTR path) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realDeleteFileA(redirected.empty() ? path : redirected.c_str());
}

BOOL WINAPI HookRemoveDirectoryW(LPCWSTR path) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realRemoveDirectoryW(redirected.empty() ? path : redirected.c_str());
}

BOOL WINAPI HookRemoveDirectoryA(LPCSTR path) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realRemoveDirectoryA(redirected.empty() ? path : redirected.c_str());
}

BOOL WINAPI HookMoveFileW(LPCWSTR source, LPCWSTR destination) {
  const std::wstring redirectedSource = RedirectWorkshopPath(source);
  const std::wstring redirectedDestination = RedirectWorkshopPath(destination);
  return g_realMoveFileW(redirectedSource.empty() ? source : redirectedSource.c_str(),
      redirectedDestination.empty() ? destination : redirectedDestination.c_str());
}

BOOL WINAPI HookMoveFileA(LPCSTR source, LPCSTR destination) {
  const std::string redirectedSource = RedirectWorkshopPathA(source);
  const std::string redirectedDestination = RedirectWorkshopPathA(destination);
  return g_realMoveFileA(
      redirectedSource.empty() ? source : redirectedSource.c_str(),
      redirectedDestination.empty() ? destination : redirectedDestination.c_str());
}

BOOL WINAPI HookMoveFileExW(LPCWSTR source, LPCWSTR destination, DWORD flags) {
  const std::wstring redirectedSource = RedirectWorkshopPath(source);
  const std::wstring redirectedDestination = RedirectWorkshopPath(destination);
  return g_realMoveFileExW(
      redirectedSource.empty() ? source : redirectedSource.c_str(),
      redirectedDestination.empty() ? destination : redirectedDestination.c_str(),
      flags);
}

BOOL WINAPI HookMoveFileExA(LPCSTR source, LPCSTR destination, DWORD flags) {
  const std::string redirectedSource = RedirectWorkshopPathA(source);
  const std::string redirectedDestination = RedirectWorkshopPathA(destination);
  return g_realMoveFileExA(
      redirectedSource.empty() ? source : redirectedSource.c_str(),
      redirectedDestination.empty() ? destination : redirectedDestination.c_str(),
      flags);
}

BOOL WINAPI HookCopyFileW(LPCWSTR source, LPCWSTR destination,
    BOOL failIfExists) {
  const std::wstring redirectedSource = RedirectWorkshopPath(source);
  const std::wstring redirectedDestination = RedirectWorkshopPath(destination);
  return g_realCopyFileW(
      redirectedSource.empty() ? source : redirectedSource.c_str(),
      redirectedDestination.empty() ? destination : redirectedDestination.c_str(),
      failIfExists);
}

BOOL WINAPI HookCopyFileA(LPCSTR source, LPCSTR destination,
    BOOL failIfExists) {
  const std::string redirectedSource = RedirectWorkshopPathA(source);
  const std::string redirectedDestination = RedirectWorkshopPathA(destination);
  return g_realCopyFileA(
      redirectedSource.empty() ? source : redirectedSource.c_str(),
      redirectedDestination.empty() ? destination : redirectedDestination.c_str(),
      failIfExists);
}

BOOL WINAPI HookSetFileAttributesW(LPCWSTR path, DWORD attributes) {
  const std::wstring redirected = RedirectWorkshopPath(path);
  return g_realSetFileAttributesW(
      redirected.empty() ? path : redirected.c_str(), attributes);
}

BOOL WINAPI HookSetFileAttributesA(LPCSTR path, DWORD attributes) {
  const std::string redirected = RedirectWorkshopPathA(path);
  return g_realSetFileAttributesA(
      redirected.empty() ? path : redirected.c_str(), attributes);
}

std::string Utf8FromWide(const wchar_t* value, int length) {
  if (length <= 0) return {};
  const int required = WideCharToMultiByte(CP_UTF8, 0, value, length,
                                           nullptr, 0, nullptr, nullptr);
  if (required <= 0) return {};
  std::string result(static_cast<size_t>(required), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, length, result.data(), required,
                      nullptr, nullptr);
  return result;
}

void PublishOutput(const void* bytes, DWORD length) {
  if (!g_isInjectedProcess || !g_hookReady || !g_session.output ||
      g_session.output == INVALID_HANDLE_VALUE || !bytes || !length) {
    return;
  }
  DWORD written = 0;
  g_realWriteFile(g_session.output, bytes, length, &written, nullptr);
}

void PublishConsoleBytes(const void* bytes, DWORD length) {
  if (!bytes || !length || length > static_cast<DWORD>(INT_MAX)) return;
  const auto input = static_cast<LPCCH>(bytes);
  int wideLength = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
      input, static_cast<int>(length), nullptr, 0);
  UINT codePage = CP_UTF8;
  DWORD flags = MB_ERR_INVALID_CHARS;
  if (wideLength <= 0) {
    codePage = GetConsoleOutputCP();
    if (!codePage) codePage = CP_OEMCP;
    flags = 0;
    wideLength = MultiByteToWideChar(codePage, flags, input,
        static_cast<int>(length), nullptr, 0);
  }
  if (wideLength <= 0) {
    PublishOutput(bytes, length);
    return;
  }
  std::wstring wide(static_cast<size_t>(wideLength), L'\0');
  MultiByteToWideChar(codePage, flags, input, static_cast<int>(length),
      wide.data(), wideLength);
  const std::string utf8 = Utf8FromWide(wide.data(), wideLength);
  PublishOutput(utf8.data(), static_cast<DWORD>(utf8.size()));
}

BOOL WINAPI HookWriteConsoleW(HANDLE console, const VOID* buffer, DWORD count,
                              LPDWORD written, LPVOID reserved) {
  const BOOL result = g_realWriteConsoleW(console, buffer, count, written, reserved);
  if (result && buffer) {
    const DWORD actual = written ? *written : count;
    const std::string utf8 = Utf8FromWide(static_cast<LPCWSTR>(buffer),
                                          static_cast<int>(actual));
    PublishOutput(utf8.data(), static_cast<DWORD>(utf8.size()));
  }
  return result;
}

BOOL WINAPI HookWriteConsoleA(HANDLE console, const VOID* buffer, DWORD count,
                              LPDWORD written, LPVOID reserved) {
  const BOOL result = g_realWriteConsoleA(console, buffer, count, written, reserved);
  if (result && buffer) {
    PublishConsoleBytes(buffer, written ? *written : count);
  }
  return result;
}

BOOL WINAPI HookWriteFile(HANDLE file, LPCVOID buffer, DWORD count,
                          LPDWORD written, LPOVERLAPPED overlapped) {
  const BOOL result = g_realWriteFile(file, buffer, count, written, overlapped);
  if (result && buffer && !overlapped && count > 0) {
    CONSOLE_SCREEN_BUFFER_INFO consoleInfo{};
    if (GetConsoleScreenBufferInfo(file, &consoleInfo)) {
      PublishConsoleBytes(buffer, written ? *written : count);
    } else if (file == GetStdHandle(STD_OUTPUT_HANDLE) ||
               file == GetStdHandle(STD_ERROR_HANDLE)) {
      PublishOutput(buffer, written ? *written : count);
    }
  }
  return result;
}

bool IsSteamCmdChild(HANDLE process) {
  wchar_t path[32768]{};
  DWORD length = static_cast<DWORD>(_countof(path));
  if (!QueryFullProcessImageNameW(process, 0, path, &length)) return false;

  std::wstring executable(path, length);
  const size_t slash = executable.find_last_of(L"\\/");
  const size_t nameStart = slash == std::wstring::npos ? 0 : slash + 1;
  const std::wstring directory = slash == std::wstring::npos
      ? L"" : executable.substr(0, slash);
  std::wstring name = executable.substr(nameStart);
  std::transform(name.begin(), name.end(), name.begin(),
      [](wchar_t value) { return static_cast<wchar_t>(towlower(value)); });

  std::wstring expected(g_session.steamDirectory);
  std::transform(expected.begin(), expected.end(), expected.begin(),
      [](wchar_t value) { return static_cast<wchar_t>(towlower(value)); });
  return name.rfind(L"steamcmd", 0) == 0 &&
      executable.size() > name.size() &&
      _wcsicmp(directory.c_str(), expected.c_str()) == 0;
}

bool HasSameArchitecture(HANDLE process) {
  BOOL currentIsWow64 = FALSE;
  BOOL targetIsWow64 = FALSE;
  return IsWow64Process(GetCurrentProcess(), &currentIsWow64) &&
      IsWow64Process(process, &targetIsWow64) &&
      currentIsWow64 == targetIsWow64;
}

bool InjectSteamCmdChild(HANDLE process) {
  HANDLE childOutput = INVALID_HANDLE_VALUE;
  HANDLE childInput = INVALID_HANDLE_VALUE;
  if (!DuplicateHandle(GetCurrentProcess(), g_session.output, process,
          &childOutput, 0, FALSE, DUPLICATE_SAME_ACCESS) ||
      !DuplicateHandle(GetCurrentProcess(), g_session.input, process,
          &childInput, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
    if (childOutput != INVALID_HANDLE_VALUE)
      DuplicateHandle(process, childOutput, GetCurrentProcess(), nullptr, 0,
                      FALSE, DUPLICATE_CLOSE_SOURCE);
    return false;
  }

  HookConfig child = g_session;
  child.output = childOutput;
  child.input = childInput;
  LPCSTR dllPaths[] = {g_dllPathAnsi};
  if (!DetourUpdateProcessWithDll(process, dllPaths, 1) ||
      !DetourCopyPayloadToProcess(process, kConfigId, &child, sizeof(child))) {
    DuplicateHandle(process, childOutput, GetCurrentProcess(), nullptr, 0,
                    FALSE, DUPLICATE_CLOSE_SOURCE);
    DuplicateHandle(process, childInput, GetCurrentProcess(), nullptr, 0,
                    FALSE, DUPLICATE_CLOSE_SOURCE);
    return false;
  }
  return true;
}

bool CompleteChildLaunch(LPPROCESS_INFORMATION processInfo,
                         DWORD originalFlags) {
  if (!processInfo || !processInfo->hProcess) return true;
  const bool callerSuspended = (originalFlags & CREATE_SUSPENDED) != 0;
  const bool steamChild = IsSteamCmdChild(processInfo->hProcess);
  const bool sameArchitecture = HasSameArchitecture(processInfo->hProcess);
  if (steamChild && sameArchitecture && !InjectSteamCmdChild(processInfo->hProcess)) {
    const DWORD error = GetLastError();
    TerminateProcess(processInfo->hProcess, error ? error : ERROR_DLL_INIT_FAILED);
    CloseHandle(processInfo->hThread);
    CloseHandle(processInfo->hProcess);
    processInfo->hThread = nullptr;
    processInfo->hProcess = nullptr;
    SetLastError(error ? error : ERROR_DLL_INIT_FAILED);
    return false;
  }
  if (!callerSuspended && ResumeThread(processInfo->hThread) == static_cast<DWORD>(-1)) {
    const DWORD error = GetLastError();
    TerminateProcess(processInfo->hProcess, error);
    SetLastError(error);
    return false;
  }
  return true;
}

BOOL WINAPI HookCreateProcessW(LPCWSTR application, LPWSTR command,
    LPSECURITY_ATTRIBUTES processAttributes, LPSECURITY_ATTRIBUTES threadAttributes,
    BOOL inheritHandles, DWORD flags, LPVOID environment, LPCWSTR currentDirectory,
    LPSTARTUPINFOW startup, LPPROCESS_INFORMATION processInfo) {
  const BOOL created = g_realCreateProcessW(application, command, processAttributes,
      threadAttributes, inheritHandles, flags | CREATE_SUSPENDED, environment,
      currentDirectory, startup, processInfo);
  const DWORD error = GetLastError();
  if (!created) {
    SetLastError(error);
    return FALSE;
  }
  const bool completed = CompleteChildLaunch(processInfo, flags);
  if (!completed) return FALSE;
  SetLastError(error);
  return TRUE;
}

BOOL WINAPI HookCreateProcessA(LPCSTR application, LPSTR command,
    LPSECURITY_ATTRIBUTES processAttributes, LPSECURITY_ATTRIBUTES threadAttributes,
    BOOL inheritHandles, DWORD flags, LPVOID environment, LPCSTR currentDirectory,
    LPSTARTUPINFOA startup, LPPROCESS_INFORMATION processInfo) {
  const BOOL created = g_realCreateProcessA(application, command, processAttributes,
      threadAttributes, inheritHandles, flags | CREATE_SUSPENDED, environment,
      currentDirectory, startup, processInfo);
  const DWORD error = GetLastError();
  if (!created) {
    SetLastError(error);
    return FALSE;
  }
  const bool completed = CompleteChildLaunch(processInfo, flags);
  if (!completed) return FALSE;
  SetLastError(error);
  return TRUE;
}

unsigned __stdcall InputThread(void*) {
  HANDLE console = GetStdHandle(STD_INPUT_HANDLE);
  DWORD originalMode = 0;
  if (GetConsoleMode(console, &originalMode)) {
    SetConsoleMode(console, originalMode & ~ENABLE_ECHO_INPUT);
  }

  char bytes[1024];
  while (true) {
    DWORD received = 0;
    if (!g_realReadFile(g_session.input, bytes, sizeof(bytes), &received, nullptr) ||
        received == 0) break;

    const int wideLength = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        bytes, static_cast<int>(received), nullptr, 0);
    if (wideLength <= 0 || wideLength > 4096) continue;
    std::wstring line(static_cast<size_t>(wideLength), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes,
        static_cast<int>(received), line.data(), wideLength);

    std::vector<INPUT_RECORD> events;
    events.reserve(line.size() * 2);
    for (wchar_t character : line) {
      if (character == L'\n') character = L'\r';
      INPUT_RECORD event{};
      event.EventType = KEY_EVENT;
      event.Event.KeyEvent.bKeyDown = TRUE;
      event.Event.KeyEvent.wRepeatCount = 1;
      event.Event.KeyEvent.uChar.UnicodeChar = character;
      events.push_back(event);
      event.Event.KeyEvent.bKeyDown = FALSE;
      events.push_back(event);
    }
    DWORD accepted = 0;
    WriteConsoleInputW(console, events.data(), static_cast<DWORD>(events.size()), &accepted);
  }
  if (originalMode) SetConsoleMode(console, originalMode);
  return 0;
}

bool InstallHooks() {
  LONG error = DetourTransactionBegin();
  if (error == NO_ERROR) error = DetourUpdateThread(GetCurrentThread());
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realWriteConsoleW), HookWriteConsoleW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realWriteConsoleA), HookWriteConsoleA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realWriteFile), HookWriteFile);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCreateFileW), HookCreateFileW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCreateFileA), HookCreateFileA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCreateDirectoryW), HookCreateDirectoryW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCreateDirectoryA), HookCreateDirectoryA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realGetFileAttributesW), HookGetFileAttributesW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realGetFileAttributesA), HookGetFileAttributesA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realGetFileAttributesExW), HookGetFileAttributesExW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realGetFileAttributesExA), HookGetFileAttributesExA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realFindFirstFileW), HookFindFirstFileW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realFindFirstFileA), HookFindFirstFileA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realDeleteFileW), HookDeleteFileW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realDeleteFileA), HookDeleteFileA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realRemoveDirectoryW), HookRemoveDirectoryW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realRemoveDirectoryA), HookRemoveDirectoryA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realMoveFileW), HookMoveFileW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realMoveFileA), HookMoveFileA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realMoveFileExW), HookMoveFileExW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realMoveFileExA), HookMoveFileExA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCopyFileW), HookCopyFileW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCopyFileA), HookCopyFileA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realSetFileAttributesW), HookSetFileAttributesW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realSetFileAttributesA), HookSetFileAttributesA);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCreateProcessW), HookCreateProcessW);
  if (error == NO_ERROR) error = DetourAttach(reinterpret_cast<PVOID*>(&g_realCreateProcessA), HookCreateProcessA);
  if (error == NO_ERROR) error = DetourTransactionCommit();
  else DetourTransactionAbort();
  return error == NO_ERROR;
}

bool CacheInjectedDllPath() {
  wchar_t path[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(g_module, path, _countof(path));
  if (!length || length >= _countof(path)) return false;
  BOOL usedDefault = FALSE;
  const int bytes = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, path, -1,
      g_dllPathAnsi, sizeof(g_dllPathAnsi), nullptr, &usedDefault);
  return bytes != 0 && !usedDefault;
}

bool CloseSessionPipe(HANDLE& pipe) {
  const bool valid = pipe && pipe != INVALID_HANDLE_VALUE;
  if (valid) CloseHandle(pipe);
  pipe = INVALID_HANDLE_VALUE;
  return valid;
}
}  // namespace

extern "C" __declspec(dllexport) BOOL CreateOutputPipe(const wchar_t* name) {
  if (!name || !*name) {
    SetLastError(ERROR_INVALID_NAME);
    return FALSE;
  }
  std::lock_guard<std::mutex> lock(g_sessionMutex);
  if (g_outputRead != INVALID_HANDLE_VALUE) {
    SetLastError(ERROR_ALREADY_INITIALIZED);
    return FALSE;
  }
  SECURITY_ATTRIBUTES security{sizeof(security), nullptr, FALSE};
  if (!CreatePipe(&g_outputRead, &g_outputWrite, &security, kBufferSize)) return FALSE;
  if (!CreatePipe(&g_inputRead, &g_inputWrite, &security, 0)) {
    CloseSessionPipe(g_outputRead);
    CloseSessionPipe(g_outputWrite);
    return FALSE;
  }
  return TRUE;
}

extern "C" __declspec(dllexport) HANDLE StartSteamCmdHooked(const wchar_t* args) {
  std::lock_guard<std::mutex> lock(g_sessionMutex);
  if (!args || !*args || g_outputRead == INVALID_HANDLE_VALUE ||
      g_job || g_process) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return nullptr;
  }

  int argumentCount = 0;
  LPWSTR* arguments = CommandLineToArgvW(args, &argumentCount);
  if (!arguments || argumentCount == 0) {
    if (arguments) LocalFree(arguments);
    SetLastError(ERROR_INVALID_PARAMETER);
    return nullptr;
  }
  wchar_t executable[32768]{};
  DWORD length = GetFullPathNameW(arguments[0], _countof(executable), executable, nullptr);
  std::wstring path(executable);
  LocalFree(arguments);
  if (!length || length >= _countof(executable)) {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    return nullptr;
  }
  const size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos || slash >= MAX_PATH) {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    return nullptr;
  }

  HookConfig config{};
  config.version = kConfigVersion;
  wcscpy_s(config.steamDirectory, path.substr(0, slash).c_str());
  const DWORD workshopLength = GetEnvironmentVariableW(
      L"WALLPAPER_ENGINE_WORKSHOP_DIR", config.workshopDirectory,
      _countof(config.workshopDirectory));
  if (workshopLength >= _countof(config.workshopDirectory)) {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    return nullptr;
  }
  std::vector<wchar_t> commandLine(args, args + wcslen(args) + 1);

  g_job = CreateJobObjectW(nullptr, nullptr);
  if (!g_job) return nullptr;
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(g_job, JobObjectExtendedLimitInformation,
                               &limits, sizeof(limits))) return nullptr;

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process{};
  if (!g_realCreateProcessW(path.c_str(), commandLine.data(), nullptr, nullptr,
      FALSE, CREATE_SUSPENDED | CREATE_NEW_CONSOLE, nullptr,
      config.steamDirectory, &startup, &process)) return nullptr;

  if (!AssignProcessToJobObject(g_job, process.hProcess)) {
    const DWORD error = GetLastError();
    TerminateProcess(process.hProcess, error);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    SetLastError(error);
    return nullptr;
  }

  HANDLE remoteOutput = INVALID_HANDLE_VALUE;
  HANDLE remoteInput = INVALID_HANDLE_VALUE;
  if (!DuplicateHandle(GetCurrentProcess(), g_outputWrite, process.hProcess,
          &remoteOutput, 0, FALSE, DUPLICATE_SAME_ACCESS) ||
      !DuplicateHandle(GetCurrentProcess(), g_inputRead, process.hProcess,
          &remoteInput, 0, FALSE, DUPLICATE_SAME_ACCESS)) {
    const DWORD error = GetLastError();
    if (remoteOutput != INVALID_HANDLE_VALUE)
      DuplicateHandle(process.hProcess, remoteOutput, GetCurrentProcess(), nullptr,
                      0, FALSE, DUPLICATE_CLOSE_SOURCE);
    TerminateProcess(process.hProcess, error);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    SetLastError(error);
    return nullptr;
  }
  config.output = remoteOutput;
  config.input = remoteInput;

  wchar_t dllPath[MAX_PATH]{};
  length = GetModuleFileNameW(g_module, dllPath, MAX_PATH);
  if (!length || length >= MAX_PATH) {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    TerminateProcess(process.hProcess, GetLastError());
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return nullptr;
  }
  BOOL usedDefault = FALSE;
  const int dllBytes = WideCharToMultiByte(CP_ACP, WC_NO_BEST_FIT_CHARS, dllPath,
      -1, g_dllPathAnsi, static_cast<int>(sizeof(g_dllPathAnsi)), nullptr,
      &usedDefault);
  if (!dllBytes || usedDefault) {
    const DWORD error = ERROR_NO_UNICODE_TRANSLATION;
    TerminateProcess(process.hProcess, error);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    SetLastError(error);
    return nullptr;
  }

  LPCSTR dllPaths[] = {g_dllPathAnsi};
  if (!DetourUpdateProcessWithDll(process.hProcess, dllPaths, 1) ||
      !DetourCopyPayloadToProcess(process.hProcess, kConfigId, &config,
                                  sizeof(config))) {
    const DWORD error = GetLastError();
    TerminateProcess(process.hProcess, error ? error : ERROR_DLL_INIT_FAILED);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    SetLastError(error ? error : ERROR_DLL_INIT_FAILED);
    return nullptr;
  }

  CloseSessionPipe(g_outputWrite);
  if (ResumeThread(process.hThread) == static_cast<DWORD>(-1)) {
    const DWORD error = GetLastError();
    TerminateProcess(process.hProcess, error);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    SetLastError(error);
    return nullptr;
  }
  CloseHandle(process.hThread);
  g_process = process.hProcess;
  g_session = config;
  return g_process;
}

extern "C" __declspec(dllexport) BOOL WaitForPipeConnection(DWORD timeout) {
  UNREFERENCED_PARAMETER(timeout);
  return g_process != nullptr && g_outputRead != INVALID_HANDLE_VALUE;
}

extern "C" __declspec(dllexport) int ReadPipeOutput(char* buffer, int size) {
  if (!buffer || size <= 0 || g_outputRead == INVALID_HANDLE_VALUE) return -1;
  DWORD available = 0;
  if (!PeekNamedPipe(g_outputRead, nullptr, 0, nullptr, &available, nullptr)) {
    const DWORD error = GetLastError();
    return error == ERROR_BROKEN_PIPE ? -1 : 0;
  }
  if (!available) {
    const DWORD status = g_job ? WaitForSingleObject(g_job, 0) : WAIT_TIMEOUT;
    return status == WAIT_OBJECT_0 ? -1 : 0;
  }
  DWORD received = 0;
  if (ReadFile(g_outputRead, buffer,
      static_cast<DWORD>((std::min)(size, static_cast<int>(available))),
      &received, nullptr)) return static_cast<int>(received);
  const DWORD error = GetLastError();
  return error == ERROR_BROKEN_PIPE ? -1 : 0;
}

extern "C" __declspec(dllexport) int WriteProcessInput(const char* bytes, int size) {
  if (!bytes || size <= 0 || g_inputWrite == INVALID_HANDLE_VALUE) return -1;
  DWORD written = 0;
  if (!WriteFile(g_inputWrite, bytes, static_cast<DWORD>(size), &written, nullptr))
    return -1;
  return static_cast<int>(written);
}

extern "C" __declspec(dllexport) BOOL IsProcessRunning(HANDLE process) {
  UNREFERENCED_PARAMETER(process);
  if (!g_job) return FALSE;
  JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting{};
  return QueryInformationJobObject(g_job, JobObjectBasicAccountingInformation,
      &accounting, sizeof(accounting), nullptr) && accounting.ActiveProcesses != 0;
}

extern "C" __declspec(dllexport) int WaitForCompletion(HANDLE process,
                                                           DWORD timeout) {
  UNREFERENCED_PARAMETER(process);
  if (!g_job || !g_process) return -1;
  const ULONGLONG started = GetTickCount64();
  while (true) {
    if (!IsProcessRunning(g_process)) {
      DWORD exitCode = 1;
      return GetExitCodeProcess(g_process, &exitCode) ? static_cast<int>(exitCode) : -1;
    }
    if (WaitForSingleObject(g_process, 25) == WAIT_FAILED) return -1;
    if (timeout != INFINITE && GetTickCount64() - started >= timeout) return -1;
  }
}

extern "C" __declspec(dllexport) void Cleanup() {
  std::lock_guard<std::mutex> lock(g_sessionMutex);
  if (g_job) CloseHandle(g_job);
  g_job = nullptr;
  if (g_process) {
    WaitForSingleObject(g_process, 5000);
    CloseHandle(g_process);
  }
  g_process = nullptr;
  CloseSessionPipe(g_outputRead);
  CloseSessionPipe(g_outputWrite);
  CloseSessionPipe(g_inputRead);
  CloseSessionPipe(g_inputWrite);
  g_session = {};
}

BOOL WINAPI DllMain(HINSTANCE module, DWORD reason, LPVOID reserved) {
  UNREFERENCED_PARAMETER(reserved);
  if (DetourIsHelperProcess()) return TRUE;
  if (reason == DLL_PROCESS_ATTACH) {
    g_module = module;
    DisableThreadLibraryCalls(module);
    DWORD payloadSize = 0;
    const auto* payload = static_cast<const HookConfig*>(
        DetourFindPayloadEx(kConfigId, &payloadSize));
    if (!payload || payloadSize != sizeof(HookConfig) ||
        payload->version != kConfigVersion || !payload->output || !payload->input) {
      return TRUE;
    }
    g_isInjectedProcess = true;
    g_session = *payload;
    DetourRestoreAfterWith();
    if (!CacheInjectedDllPath()) return FALSE;
    g_hookReady = InstallHooks();
    if (g_hookReady) {
      const uintptr_t thread = _beginthreadex(nullptr, 0, InputThread, nullptr, 0, nullptr);
      if (thread) CloseHandle(reinterpret_cast<HANDLE>(thread));
      constexpr char status[] = "[hook] attached to SteamCMD process\r\n";
      PublishOutput(status, sizeof(status) - 1);
    }
  }
  return TRUE;
}
