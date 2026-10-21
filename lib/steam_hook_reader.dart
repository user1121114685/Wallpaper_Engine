// 导入必要的库
import 'dart:ffi';
import 'dart:io' show systemEncoding; // 导入 systemEncoding

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

void SteamCommand(String command) {
  print('准备使用 CreateProcess 运行 ping.exe 并捕获输出...');

  // 1. 定义我们需要的所有 FFI 指针。
  // 将它们在 try 外部声明为 nullable，以便 finally 块可以访问它们。
  Pointer<SECURITY_ATTRIBUTES> pSec = nullptr;
  Pointer<HANDLE> hReadPipe = nullptr, hWritePipe = nullptr;
  Pointer<STARTUPINFO> lpStartupInfo = nullptr;
  Pointer<PROCESS_INFORMATION> lpProcessInformation = nullptr;
  Pointer<Utf16> lpCommandLine = nullptr;
  Pointer<Uint8> readBuffer = nullptr;
  Pointer<DWORD> bytesRead = nullptr;

  try {
    // 2. 为可继承的句柄设置 SECURITY_ATTRIBUTES
    pSec = calloc<SECURITY_ATTRIBUTES>();
    pSec.ref.nLength = sizeOf<SECURITY_ATTRIBUTES>();
    pSec.ref.bInheritHandle = TRUE; // 关键：允许子进程继承句柄
    pSec.ref.lpSecurityDescriptor = nullptr;

    // 3. 创建匿名管道
    hReadPipe = calloc<HANDLE>();
    hWritePipe = calloc<HANDLE>();
    if (CreatePipe(hReadPipe, hWritePipe, pSec, 0) == FALSE) {
      throw Exception('CreatePipe 失败: ${GetLastError()}');
    }

    // 4. 设置 STARTUPINFO 以重定向句柄
    // 这是你控制窗口和 I/O 的地方
    lpStartupInfo = calloc<STARTUPINFO>();
    lpStartupInfo.ref.cb = sizeOf<STARTUPINFO>();
    lpStartupInfo.ref.dwFlags = STARTF_USESTDHANDLES; // | STARTF_USESHOWWINDOW;

    // STARTF_USESTDHANDLES 告诉 CreateProcess 使用下面的句柄
    // 注意：当使用 STARTF_USESTDHANDLES 时，
    // 控制台应用 (如 ping) 的窗口将不会显示，这是正常的。
    lpStartupInfo.ref.hStdInput = NULL; // 我们不提供输入
    lpStartupInfo.ref.hStdOutput = hWritePipe.value; // 重定向标准输出
    lpStartupInfo.ref.hStdError = hWritePipe.value; // 重定向标准错误到同一管道

    // 如果你想"显示窗口"（例如 SW_SHOWNORMAL），你需要添加 STARTF_USESHOWWINDOW
    // lpStartupInfo.ref.dwFlags |= STARTF_USESHOWWINDOW;
    // lpStartupInfo.ref.wShowWindow = SW_SHOWNORMAL;
    // ...但如前所述，对于控制台应用，I/O 重定向会覆盖窗口显示。

    // 5. 准备其他 CreateProcess 参数
    lpProcessInformation = calloc<PROCESS_INFORMATION>();

    // 你要运行的命令

    lpCommandLine = command.toNativeUtf16();

    print('正在执行: $command\n');

    // 6. 调用 CreateProcess
    // 我们将 bInheritHandles 设置为 TRUE，以便子进程继承我们的管道写入句柄
    if (CreateProcess(
          nullptr, // lpApplicationName (使用 lpCommandLine)
          lpCommandLine, // lpCommandLine
          nullptr, // lpProcessAttributes
          nullptr, // lpThreadAttributes
          TRUE, // bInheritHandles - 必须为 TRUE
          0, // dwCreationFlags - 0 表示默认行为
          nullptr, // lpEnvironment
          nullptr, // lpCurrentDirectory
          lpStartupInfo, // lpStartupInfo (指向我们的结构体)
          lpProcessInformation, // lpProcessInformation (接收进程信息)
        ) ==
        FALSE) {
      throw Exception('CreateProcess 失败: ${GetLastError()}');
    }

    // 7. 在父进程中，我们必须关闭管道的"写入端"！
    // 否则，ReadFile 会永远等待，因为它认为写入可能尚未完成。
    CloseHandle(hWritePipe.value);
    hWritePipe.value = NULL; // 标记为已关闭

    // 8. 循环从管道的"读取端"读取数据
    final outputBytes = <int>[]; // 用于存储所有输出字节
    readBuffer = calloc<Uint8>(4096); // 4k 缓冲区
    bytesRead = calloc<DWORD>();

    while (true) {
      final result = ReadFile(
        hReadPipe.value, // 从读取端读取
        readBuffer.cast(), // 缓冲区
        4096, // 缓冲区大小
        bytesRead, // 接收实际读取的字节数
        nullptr, // (用于 Overlapped I/O)
      );

      // 检查 ReadFile 的结果
      if (result == FALSE || bytesRead.value == 0) {
        final error = GetLastError();
        if (error == ERROR_BROKEN_PIPE) {
          // 这是正常的：管道的另一端（子进程）已关闭。
          // 我们已经读完了所有数据。
          break;
        } else {
          // 发生了一些意外错误
          throw Exception('ReadFile 失败: $error');
        }
      }

      // 将读取到的字节添加到我们的列表中
      for (var i = 0; i < bytesRead.value; i++) {
        outputBytes.add(readBuffer[i]);
      }
    }

    // 9. 将字节解码为字符串
    // 使用 systemEncoding 来正确处理本地字符（例如 GBK）
    final outputString = systemEncoding.decode(outputBytes);

    print('--- EXE 控制台输出开始 ---');
    print(outputString);
    print('--- EXE 控制台输出结束 ---');

    // 10. 等待子进程完全退出
    WaitForSingleObject(lpProcessInformation.ref.hProcess, INFINITE);
    print('\n子进程已退出。');
  } catch (e) {
    print('发生错误: $e');
  } finally {
    // 11. 关键：清理所有资源
    print('正在清理资源...');

    // 关闭所有打开的句柄
    if (hReadPipe != nullptr && hReadPipe.value != NULL)
      CloseHandle(hReadPipe.value);
    if (hWritePipe != nullptr && hWritePipe.value != NULL)
      CloseHandle(hWritePipe.value); // 以防万一
    if (lpProcessInformation != nullptr) {
      if (lpProcessInformation.ref.hProcess != NULL)
        CloseHandle(lpProcessInformation.ref.hProcess);
      if (lpProcessInformation.ref.hThread != NULL)
        CloseHandle(lpProcessInformation.ref.hThread);
    }

    // 释放所有 calloc 分配的内存
    if (pSec != nullptr) calloc.free(pSec);
    if (hReadPipe != nullptr) calloc.free(hReadPipe);
    if (hWritePipe != nullptr) calloc.free(hWritePipe);
    if (lpStartupInfo != nullptr) calloc.free(lpStartupInfo);
    if (lpProcessInformation != nullptr) calloc.free(lpProcessInformation);
    if (lpCommandLine != nullptr) calloc.free(lpCommandLine);
    if (readBuffer != nullptr) calloc.free(readBuffer);
    if (bytesRead != nullptr) calloc.free(bytesRead);
  }
}
