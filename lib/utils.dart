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
ValueNotifier<int> logsNotifier = ValueNotifier<int>(0);
TextEditingController urlController = TextEditingController();
String wallpaper64 = "";
String? _pendingSteamCmdLine;
final ValueNotifier<int> steamGuardPromptNotifier = ValueNotifier<int>(0);
final SteamGuardPromptDetector _steamGuardPromptDetector =
    SteamGuardPromptDetector();

bool isReleaseVersionNewer(String installedVersion, String releaseTag) {
  final installed = _releaseVersionComponents(installedVersion);
  final release = _releaseVersionComponents(releaseTag);
  if (installed == null || release == null) return false;

  for (var index = 0; index < installed.length; index++) {
    if (release[index] != installed[index]) {
      return release[index] > installed[index];
    }
  }
  return false;
}

List<int>? _releaseVersionComponents(String version) {
  final match = RegExp(
    r'^[vV]?(\d+(?:\.\d+){0,2})(?:[-+][0-9A-Za-z.-]+)?$',
  ).firstMatch(version.trim());
  if (match == null) return null;

  final components = match
      .group(1)!
      .split('.')
      .map(int.parse)
      .toList(growable: true);
  while (components.length < 3) {
    components.add(0);
  }
  return components;
}

class SteamGuardPromptDetector {
  static const _prompt = 'steam guard code:';
  String _tail = '';

  bool add(String output) {
    final combined = '$_tail$output'.toLowerCase();
    final found = combined.contains(_prompt);
    final keepLength = _prompt.length - 1;
    _tail = combined.length <= keepLength
        ? combined
        : combined.substring(combined.length - keepLength);
    return found;
  }

  void reset() => _tail = '';
}

Future logTextAdd(String log) async {
  _pendingSteamCmdLine = null;
  logText.insert(0, log);
  if (logText.length > 1000) logText.removeLast();
  logsNotifier.value++;
}

void logSteamCmdOutput(String output) {
  if (output.isEmpty) return;
  if (_steamGuardPromptDetector.add(output)) {
    steamGuardPromptNotifier.value++;
  }
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
  logsNotifier.value++;
}

void finishSteamCmdOutput() {
  _pendingSteamCmdLine = null;
  _steamGuardPromptDetector.reset();
}

Future logTextAddList(List<String> log) async {
  _pendingSteamCmdLine = null;
  logText.insertAll(0, log.reversed);
  if (logText.length > 1000) logText.removeRange(1000, logText.length);
  logsNotifier.value++;
}

// 保持原有的工具函数不变
Future<String> getPreferences(String keyword) async {
  final prefs = await SharedPreferences.getInstance();
  if (keyword == "wallpaper64.exe") {
    wallpaper64 = prefs.getString(keyword).toString();
  }
  return prefs.getString(keyword).toString();
}

Future<Directory?> getWorkshopDownloadDirectory() async {
  final wallpaperExecutable = await getPreferences('wallpaper64.exe');
  if (wallpaperExecutable == 'null' || wallpaperExecutable.isEmpty) return null;

  final executable = File(wallpaperExecutable);
  if (!await executable.exists()) return null;

  final separator = Platform.pathSeparator;
  final directory = Directory(
    '${executable.parent.path}${separator}projects${separator}defaultprojects',
  );
  await directory.create(recursive: true);
  return directory;
}
