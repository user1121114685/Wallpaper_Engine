import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';

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

Future logTextAdd(String log) async {
  logText.insert(0, log);
  logsNotifier.value = log;
}

bool _showSteamGuardCode = false;
Future logTextAddList(List<String> log) async {
  logText.insertAll(0, log.reversed);
  logsNotifier.value = log.join();
  if (log.contains("Steam Guard code:") && !_showSteamGuardCode) {
    _showSteamGuardCode = true;
    showGeneralDialog(
      context: Get.context!,
      pageBuilder:
          (
            BuildContext buildContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return TDConfirmDialog(
              title: "邮件验证码",
              content: "请前往你的邮箱，将验证码填写到steamCMD运行框中",
              buttonStyle: TDDialogButtonStyle.text,
            );
          },
    );
  }
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
  int _logLines = 0;
  LogWatcher(this._logFile);

  void startWatching() async {
    // 开始监听前先清空文件
    await _clearLogFile();

    // 使用定时器每500毫秒检查一次文件变化
    _timer = Timer.periodic(Duration(milliseconds: 500), (timer) async {
      await _checkFileChanges();
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

      // 检查文件大小或修改时间是否有变化
      if (currentSize != _lastFileSize ||
          (_lastModified != null && currentModified != _lastModified)) {
        _lastFileSize = currentSize;
        _lastModified = currentModified;

        // 读取新内容
        final newLines = await _readNewLogContent(_logFile);
        if (newLines.isNotEmpty) {
          _logLines = newLines.length;
          logTextAddList(newLines);
        }
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
      // 同时清空内存中的日志行
      _logLines = 0;
      // 重置文件状态跟踪
      _lastFileSize = 0;
      _lastModified = null;
    } catch (e) {
      print('清空日志文件时出错: $e');
    }
  }

  Future<List<String>> _readNewLogContent(File file) async {
    final content = await file.readAsLines();
    return content.sublist(_logLines);
  }

  void stopWatching() {
    _timer?.cancel();
  }
}
