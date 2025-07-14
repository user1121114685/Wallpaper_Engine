import 'dart:io';

String executableDirPath() {
  // 获取解析后的完整可执行文件路径（绝对路径）
  String resolvedExecutablePath = Platform.resolvedExecutable;

  // 获取可执行文件所在的目录
  Directory executableDir = Directory(resolvedExecutablePath).parent;
  String executableDirPath = executableDir.path;
  print('可执行文件所在目录: $executableDirPath');
  return executableDirPath;
}
