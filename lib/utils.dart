import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

String executableDirPath() {
  // 获取解析后的完整可执行文件路径（绝对路径）
  String resolvedExecutablePath = Platform.resolvedExecutable;

  // 获取可执行文件所在的目录
  Directory executableDir = Directory(resolvedExecutablePath).parent;
  String executableDirPath = executableDir.path;
  print('可执行文件所在目录: $executableDirPath');
  return executableDirPath;
}

List<String> logText = [];
ValueNotifier<String> logsNotifier = ValueNotifier<String>("");
TextEditingController urlController = TextEditingController();
String wallpaper64 = "";
String? _pendingSteamCmdLine;

Future logTextAdd(String log) async {
  _pendingSteamCmdLine = null;
  logText.insert(0, log);
  if (logText.length > 1000) logText.removeLast();
  logsNotifier.value = log;
}

void logSteamCmdOutput(String output) {
  if (output.isEmpty) return;
  final normalized = output.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final chunks = normalized.split('\n');
  var first = chunks.first;
  if (_pendingSteamCmdLine != null) {
    final previousIndex = logText.indexOf(_pendingSteamCmdLine!);
    if (previousIndex >= 0) logText.removeAt(previousIndex);
    first = '$_pendingSteamCmdLine$first';
    _pendingSteamCmdLine = null;
  }

  final completed = <String>[];
  if (chunks.length == 1) {
    if (first.isNotEmpty) _pendingSteamCmdLine = first;
  } else if (first.isNotEmpty) {
    completed.add(first);
  }
  for (var index = 1; index < chunks.length; index++) {
    final chunk = chunks[index];
    if (index == chunks.length - 1) {
      if (chunk.isNotEmpty) _pendingSteamCmdLine = chunk;
    } else if (chunk.isNotEmpty) {
      completed.add(chunk);
    }
  }

  if (completed.isNotEmpty) logText.insertAll(0, completed.reversed);
  if (_pendingSteamCmdLine != null) logText.insert(0, _pendingSteamCmdLine!);
  if (logText.length > 1000) logText.removeRange(1000, logText.length);
  logsNotifier.value = output;
}

void finishSteamCmdOutput() {
  _pendingSteamCmdLine = null;
}

Future logTextAddList(List<String> log) async {
  _pendingSteamCmdLine = null;
  logText.insertAll(0, log.reversed);
  if (logText.length > 1000) logText.removeRange(1000, logText.length);
  logsNotifier.value = log.join();
}

// 保持原有的工具函数不变
Future<String> getPreferences(String keyword) async {
  final prefs = await SharedPreferences.getInstance();
  if (keyword == "wallpaper64.exe") {
    wallpaper64 = prefs.getString(keyword).toString();
  }
  return prefs.getString(keyword).toString();
}

Future doLink(bool relink) async {
  String runDir = executableDirPath();
  String dlDir = await getPreferences("wallpaper64.exe");
  dlDir = dlDir.replaceAll("\\wallpaper64.exe", "");
  String path_431960 =
      "$runDir\\data\\flutter_assets\\assets\\steamcmd\\steamapps\\workshop\\content\\431960";
  Future del_431960() async {
    try {
      var directory_431960 = Directory(path_431960);
      if (directory_431960.existsSync()) {
        logTextAdd("431960文件夹删除中....");
        directory_431960.delete(recursive: true);
      }
      var file_431960 = File(path_431960);
      if (file_431960.existsSync()) {
        logTextAdd("431960文件删除中....");
        file_431960.delete();
      }
    } catch (e) {
      logTextAdd("431960文件夹删除失败 $e");
    }
  }

  Future check_431960() async {
    var file_431960 = File(path_431960);
    FileSystemEntityType type = FileSystemEntity.typeSync(
      file_431960.path,
      followLinks: false,
    );

    //
    //    FileSystemEntityType.file,
    //     FileSystemEntityType.directory,
    //     FileSystemEntityType.link,
    //     FileSystemEntityType.unixDomainSock,
    //     FileSystemEntityType.pipe,
    //     FileSystemEntityType.notFound,
    if (type != FileSystemEntityType.link) {
      logTextAdd("431960 连接不存在....");
      del_431960().then((value) {
        Link(path_431960)
            .create("$dlDir\\projects\\defaultprojects\\", recursive: true)
            .then((value) => logTextAdd("431960 连接已建立完毕...."));
      });
    } else {
      if (relink) {
        logTextAdd("431960连接重建中....");
        del_431960().then((value) {
          Link(path_431960)
              .create("$dlDir\\projects\\defaultprojects\\", recursive: true)
              .then((value) => logTextAdd("431960 连接已建立完毕...."));
        });
      }
    }
  }

  try {
    check_431960();
  } catch (e) {
    logTextAdd("431960文件夹建立失败 $e");
  }
}

class LogWatcher {
  final File _logFile;
  Timer? _timer;
  int _lastFileSize = 0;
  DateTime? _lastModified;
  int _logLines = 0; // 跟踪已处理的行数
  bool _checking = false;

  LogWatcher(this._logFile);

  void startWatching() async {
    // 开始监听前先清空文件
    await _clearLogFile();

    // 使用定时器每500毫秒检查一次文件变化
    _timer = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      if (!_checking) {
        _checking = true;
        await _checkFileChanges();
        _checking = false;
      }
    });
  }

  Future<void> _checkFileChanges() async {
    try {
      if (!await _logFile.exists()) {
        return;
      }

      final stat = await _logFile.stat();
      final currentSize = stat.size;
      final currentModified = stat.modified;

      // 检查文件是否有变化
      if (currentSize != _lastFileSize ||
          (_lastModified != null && currentModified.isAfter(_lastModified!))) {
        // 读取新内容
        final newLines = await _readNewLogContent();
        if (newLines.isNotEmpty) {
          // 先更新已处理行数，再添加新行
          _logLines += newLines.length;
          await logTextAddList(newLines);
        }

        // 更新文件状态跟踪
        _lastFileSize = currentSize;
        _lastModified = currentModified;
      }
    } catch (e) {
      print('检查文件变化时出错: $e');
    }
  }

  Future<void> _clearLogFile() async {
    if (!await _logFile.exists()) {
      return;
    }
    try {
      // 清空文件内容
      await _logFile.writeAsString('');
      // 重置所有状态
      _logLines = 0;
      _lastFileSize = 0;
      _lastModified = null;
    } catch (e) {
      print('清空日志文件时出错: $e');
    }
  }

  Future<List<String>> _readNewLogContent() async {
    try {
      final content = await _logFile.readAsLines();
      final totalLines = content.length;

      // 如果当前文件行数小于已处理行数，说明文件被清空或重写了
      if (totalLines < _logLines) {
        _logLines = 0;
        return [];
      }

      // 返回新增的行
      if (totalLines > _logLines) {
        return content.sublist(_logLines);
      }

      return [];
    } catch (e) {
      print('读取日志内容时出错: $e');
      return [];
    }
  }

  void stopWatching() {
    _timer?.cancel();
    _timer = null;
  }
}
