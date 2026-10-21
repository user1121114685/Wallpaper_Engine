#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>

namespace {
void Console(const wchar_t* text) {
  DWORD written = 0;
  WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE), text,
                static_cast<DWORD>(wcslen(text)), &written, nullptr);
}

int Child() {
  SetConsoleOutputCP(936);
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
  if (argc > 1 && wcscmp(argv[1], L"--child") == 0) return Child();
  Console(L"[fixture] starting the x64 SteamCMD process\r\n");
  char executable[MAX_PATH]{};
  if (!GetModuleFileNameA(nullptr, executable, MAX_PATH)) return 84;
  std::string command = "\"" + std::string(executable) + "\" --child";
  std::vector<char> writable(command.begin(), command.end());
  writable.push_back('\0');
  STARTUPINFOA startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION child{};
  if (!CreateProcessA(executable, writable.data(), nullptr, nullptr, FALSE,
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
