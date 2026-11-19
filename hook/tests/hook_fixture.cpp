#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdio>
#include <cstring>
#include <cwchar>
#include <string>
#include <vector>

namespace {
void Console(const wchar_t* text) {
  DWORD written = 0;
  WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE), text,
                static_cast<DWORD>(wcslen(text)), &written, nullptr);
}

bool VerifyWorkshopRedirect(const wchar_t* targetDirectory) {
  if (!targetDirectory || !*targetDirectory) return false;

  wchar_t executable[MAX_PATH]{};
  const DWORD length = GetModuleFileNameW(nullptr, executable, MAX_PATH);
  if (!length || length >= MAX_PATH) return false;
  wchar_t* separator = wcsrchr(executable, L'\\');
  if (!separator) return false;
  *separator = L'\0';

  const std::wstring workshopItem = std::wstring(executable) +
      L"\\steamapps\\workshop\\content\\431960\\fixture_item";
  if (!CreateDirectoryW(workshopItem.c_str(), nullptr) &&
      GetLastError() != ERROR_ALREADY_EXISTS) {
    return false;
  }

  const std::wstring temporary = workshopItem + L"\\fixture.tmp";
  const std::wstring downloaded = workshopItem + L"\\fixture.txt";
  HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr,
      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  constexpr char payload[] = "redirected workshop file";
  DWORD written = 0;
  const BOOL saved = WriteFile(file, payload, sizeof(payload) - 1, &written, nullptr);
  CloseHandle(file);
  if (!saved || written != sizeof(payload) - 1 ||
      !MoveFileExW(temporary.c_str(), downloaded.c_str(),
                   MOVEFILE_REPLACE_EXISTING)) {
    return false;
  }

  const std::wstring targetFile = std::wstring(targetDirectory) +
      L"\\fixture_item\\fixture.txt";
  file = CreateFileW(targetFile.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  char actual[sizeof(payload)]{};
  DWORD received = 0;
  const BOOL read = ReadFile(file, actual, sizeof(actual), &received, nullptr);
  CloseHandle(file);
  if (!read || received != sizeof(payload) - 1 ||
      memcmp(actual, payload, sizeof(payload) - 1) != 0) {
    return false;
  }
  Console(L"[fixture] workshop path redirected\r\n");
  return true;
}

int Child(const wchar_t* targetDirectory) {
  SetConsoleOutputCP(936);
  if (!VerifyWorkshopRedirect(targetDirectory)) return 87;
  const char ansiLog[] =
      "[fixture] ANSI log: \xd1\xe9\xd6\xa4\xc2\xeb\xb4\xa6\xc0\xed\xcd\xa8\xb9\xfd\r\n";
  DWORD ansiWritten = 0;
  WriteConsoleA(GetStdHandle(STD_OUTPUT_HANDLE), ansiLog,
                static_cast<DWORD>(sizeof(ansiLog) - 1), &ansiWritten, nullptr);
  Console(L"Steam Guard code: ");
  char input[32]{};
  DWORD received = 0;
  if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE), input, sizeof(input) - 1,
                &received, nullptr)) {
    Console(L"\r\n[fixture] input read failed\r\n");
    return 81;
  }
  input[received] = '\0';
  std::string response = "[fixture] input received after child relaunch: ";
  response.append(input, received);
  response.append("\r\n");
  DWORD written = 0;
  const HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
  if (!WriteFile(output, response.data(), static_cast<DWORD>(response.size()),
                 &written, nullptr)) {
    return 82;
  }
  return std::string(input).find("AB12C") == std::string::npos ? 83 : 0;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc > 1 && wcscmp(argv[1], L"--child") == 0) {
    wchar_t targetDirectory[MAX_PATH]{};
    if (argc > 2) {
      wcsncpy_s(targetDirectory, argv[2], _TRUNCATE);
    } else {
      GetEnvironmentVariableW(L"WALLPAPER_ENGINE_WORKSHOP_DIR",
          targetDirectory, _countof(targetDirectory));
    }
    return Child(targetDirectory);
  }
  Console(L"[fixture] starting the x64 SteamCMD process\r\n");
  wchar_t targetDirectory[MAX_PATH]{};
  if (!GetEnvironmentVariableW(L"WALLPAPER_ENGINE_WORKSHOP_DIR",
          targetDirectory, _countof(targetDirectory))) {
    return 84;
  }
  wchar_t executable[MAX_PATH]{};
  if (!GetModuleFileNameW(nullptr, executable, MAX_PATH)) return 84;
  std::wstring command = L"\"" + std::wstring(executable) +
      L"\" --child \"" + targetDirectory + L"\"";
  std::vector<wchar_t> writable(command.begin(), command.end());
  writable.push_back(L'\0');
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  if (!CreateProcessW(executable, writable.data(), nullptr, nullptr, FALSE,
                      0, nullptr, nullptr, &startup, &child)) {
    Console(L"[fixture] child process did not start\r\n");
    return 85;
  }
  WaitForSingleObject(child.hProcess, 10000);
  DWORD result = 0;
  if (GetExitCodeProcess(child.hProcess, &result) && result == STILL_ACTIVE) {
    TerminateProcess(child.hProcess, 86);
    result = 86;
  }
  CloseHandle(child.hThread);
  CloseHandle(child.hProcess);
  wchar_t exitMessage[64]{};
  swprintf_s(exitMessage, L"[fixture] child exit code: %lu\r\n", result);
  Console(exitMessage);
  Console(L"[fixture] SteamCMD process exited\r\n");
  return static_cast<int>(result);
}
