#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <fcntl.h>
#include <io.h>
#include <cstdio>
#include <string>
#include <vector>

using CreatePipeFn = BOOL (*)(const wchar_t*);
using StartFn = HANDLE (*)(const wchar_t*);
using ReadOutputFn = int (*)(char*, int);
using WriteInputFn = int (*)(const char*, int);
using IsRunningFn = BOOL (*)(HANDLE);
using WaitFn = int (*)(HANDLE, DWORD);
using CleanupFn = void (*)();

std::wstring QuoteArgument(const std::wstring& argument) {
  if (argument.find_first_of(L" \t\"") == std::wstring::npos) return argument;
  std::wstring result(1, L'"');
  size_t slashes = 0;
  for (wchar_t ch : argument) {
    if (ch == L'\\') {
      ++slashes;
    } else if (ch == L'"') {
      result.append(slashes * 2 + 1, L'\\');
      result.push_back(ch);
      slashes = 0;
    } else {
      result.append(slashes, L'\\');
      slashes = 0;
      result.push_back(ch);
    }
  }
  result.append(slashes * 2, L'\\');
  result.push_back(L'"');
  return result;
}

void ReportError(const wchar_t* operation) {
  std::fwprintf(stderr, L"[steamcmd] %ls failed (Windows error %lu)\n",
                operation, GetLastError());
  std::fflush(stderr);
}

int wmain(int argc, wchar_t** argv) {
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stdin), _O_BINARY);
  if (argc < 2) {
    std::fputs("Usage: steamcmd_worker.exe <steamcmd.exe> [SteamCMD arguments...]\n", stderr);
    return 64;
  }

  std::vector<wchar_t> commandLine;
  for (int index = 1; index < argc; ++index) {
    if (index != 1) commandLine.push_back(L' ');
    const std::wstring quoted = QuoteArgument(argv[index]);
    commandLine.insert(commandLine.end(), quoted.begin(), quoted.end());
  }
  commandLine.push_back(L'\0');

  wchar_t dllPath[MAX_PATH]{};
  const DWORD dllLength = GetModuleFileNameW(nullptr, dllPath, MAX_PATH);
  if (!dllLength || dllLength >= MAX_PATH) {
    ReportError(L"locating the launcher");
    return 70;
  }
  wchar_t* separator = wcsrchr(dllPath, L'\\');
  if (!separator) {
    SetLastError(ERROR_BAD_PATHNAME);
    ReportError(L"locating the hook DLL");
    return 70;
  }
  *separator = L'\0';
  std::wstring libraryPath = dllPath;
  libraryPath.append(L"\\steamcmd_hook.dll");
  HMODULE hook = LoadLibraryW(libraryPath.c_str());
  if (!hook) {
    ReportError(L"loading steamcmd_hook.dll");
    return 70;
  }

  const auto createPipe = reinterpret_cast<CreatePipeFn>(GetProcAddress(hook, "CreateOutputPipe"));
  const auto start = reinterpret_cast<StartFn>(GetProcAddress(hook, "StartSteamCmdHooked"));
  const auto readOutput = reinterpret_cast<ReadOutputFn>(GetProcAddress(hook, "ReadPipeOutput"));
  const auto writeInput = reinterpret_cast<WriteInputFn>(GetProcAddress(hook, "WriteProcessInput"));
  const auto isRunning = reinterpret_cast<IsRunningFn>(GetProcAddress(hook, "IsProcessRunning"));
  const auto wait = reinterpret_cast<WaitFn>(GetProcAddress(hook, "WaitForCompletion"));
  const auto cleanup = reinterpret_cast<CleanupFn>(GetProcAddress(hook, "Cleanup"));
  if (!createPipe || !start || !readOutput || !writeInput || !isRunning || !wait || !cleanup) {
    std::fputs("[steamcmd] hook DLL is missing a required interactive I/O export\n", stderr);
    FreeLibrary(hook);
    return 70;
  }

  if (!createPipe(L"steamcmd_output")) {
    ReportError(L"creating SteamCMD I/O pipes");
    cleanup();
    FreeLibrary(hook);
    return 70;
  }
  const HANDLE process = start(commandLine.data());
  if (!process) {
    ReportError(L"starting hooked SteamCMD");
    cleanup();
    FreeLibrary(hook);
    return 71;
  }

  constexpr int bufferSize = 8192;
  std::vector<char> output(bufferSize);
  HANDLE inputThread = CreateThread(nullptr, 0,
      [](void* parameter) -> DWORD {
        auto writer = static_cast<WriteInputFn>(parameter);
        char input[256];
        while (true) {
          DWORD available = 0;
          HANDLE standardInput = GetStdHandle(STD_INPUT_HANDLE);
          if (!PeekNamedPipe(standardInput, nullptr, 0, nullptr, &available, nullptr)) {
            const DWORD error = GetLastError();
            if (error != ERROR_INVALID_FUNCTION && error != ERROR_INVALID_HANDLE) break;
            available = 1;
          }
          if (available == 0) {
            Sleep(15);
            continue;
          }
          DWORD received = 0;
          if (!ReadFile(standardInput, input, sizeof(input), &received, nullptr) || !received) break;
          const int written = writer(input, static_cast<int>(received));
          if (written != static_cast<int>(received)) {
            std::fputs("[steamcmd] unable to send console input to SteamCMD\n", stderr);
            std::fflush(stderr);
          }
        }
        return 0;
      }, reinterpret_cast<void*>(writeInput), 0, nullptr);

  while (true) {
    const int received = readOutput(output.data(), bufferSize);
    if (received > 0) {
      DWORD written = 0;
      HANDLE standardOutput = GetStdHandle(STD_OUTPUT_HANDLE);
      WriteFile(standardOutput, output.data(), static_cast<DWORD>(received), &written, nullptr);
    } else if (received == -1 && !isRunning(process)) {
      break;
    } else if (received == 0) {
      Sleep(5);
    }
    if (WaitForSingleObject(process, 0) == WAIT_OBJECT_0 && !isRunning(process) &&
        received == -1) break;
  }

  const int exitCode = wait(process, INFINITE);
  cleanup();
  if (inputThread) {
    CancelSynchronousIo(inputThread);
    WaitForSingleObject(inputThread, 1000);
    CloseHandle(inputThread);
  }
  FreeLibrary(hook);
  return exitCode < 0 ? 1 : exitCode;
}
