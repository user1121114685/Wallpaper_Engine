import 'dart:io';

import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:dio/dio.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:get/get.dart' hide Response;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallpaper_engine_workshop_downloader/steam_guard_input.dart';
import 'package:wallpaper_engine_workshop_downloader/steamcmd_ffi.dart';
import 'package:wallpaper_engine_workshop_downloader/utils.dart';

Future main() async {
  _initLogSystem();
  runApp(const MyApp());
}

void _initLogSystem() async {
  String path = executableDirPath();
  String logFile =
      "$path\\data\\flutter_assets\\assets\\steamcmd\\logs\\console_log.txt";
  File file = File(logFile);

  LogWatcher(file).startWatching();
}

bool multidown = false;
final ValueNotifier<bool> _steamCmdRunning = ValueNotifier(false);
final ValueNotifier<bool> _steamCmdInputReady = ValueNotifier(false);
SteamCmdHook? _activeSteamCmd;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late TThemeData _themeData;

  @override
  void initState() {
    super.initState();
    _themeData = TThemeData.defaultData();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Wallpaper Engine 下载器',
      theme: TThemeBuilder.light(
        _themeData,
      ).useSystemChineseFont(Brightness.light),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwdController = TextEditingController();
  bool _isPasswordVisible = false;
  String? appVersion;

  Future<void> _loadAppVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      appVersion = packageInfo.version;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _launchUrl("https://steamcommunity.com/app/431960/workshop/");
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('SteamName') ?? '';
      _passwdController.text = prefs.getString('SteamPSWD') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tTheme.grayColor1,
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCredentialsSection(),
                  SizedBox(height: 24),

                  // 下载区域
                  _buildDownloadSection(),
                  SizedBox(height: 24),
                  _buildSoftwareInformation(appVersion),
                ],
              ),
            ),
            SizedBox(width: 24),
            // 日志区域
            Flexible(child: _buildLogSection()),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.folder, color: context.tTheme.brandColor7),
            SizedBox(width: 8),
            Text(
              '壁纸路径设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.tTheme.textColorPrimary,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        FutureBuilder(
          future: getPreferences("wallpaper64.exe"),
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            bool hasPath = snapshot.data.toString().contains("wallpaper64.exe");
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TTag(
                  hasPath ? "已选择 wallpaper64.exe" : "未选择 wallpaper64.exe",
                  colorPreset: hasPath
                      ? TTagColorPreset.success
                      : TTagColorPreset.warning,
                  variant: TTagVariant.light,
                  icon: hasPath ? Icons.check_circle : Icons.cancel,
                ),
                SizedBox(width: 16),
                TButton(
                  child: const Text('选择文件'),
                  colorPreset: TButtonColorPreset.primary,
                  variant: TButtonVariant.outline,
                  icon: const Icon(Icons.folder_open),
                  onPressed: () async {
                    final file = OpenFilePicker()
                      ..filterSpecification = {
                        'Wallpaper Engine': 'wallpaper64.exe',
                      }
                      ..defaultFilterIndex = 0
                      ..title = '选择Wallpaper Engine 启动文件';
                    File? result = file.getFile();
                    if (result != null) {
                      final prefs = await SharedPreferences.getInstance();
                      prefs.setString('wallpaper64.exe', result.path);
                      doLink(true);
                      setState(() {});
                      TToast.showSuccess('文件选择成功!', context: Get.context!);
                    }
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCredentialsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFileSelectionSection(),
            Row(
              children: [
                Icon(Icons.person, color: context.tTheme.brandColor7),
                SizedBox(width: 8),
                Text(
                  'Steam 账号设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.tTheme.textColorPrimary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: TInput(
                    prefix: const Text('账号'),
                    controller: _nameController,
                    hintText: '请输入Steam账号',
                  ),
                ),
                SizedBox(width: 16),
                Flexible(
                  child: TInput(
                    prefix: const Text('密码'),
                    controller: _passwdController,
                    hintText: '请输入Steam密码',
                    obscureText: !_isPasswordVisible,
                    suffix: TButton(
                      variant: TButtonVariant.text,
                      shape: TButtonShape.square,
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TButton(
                  child: const Text('保存账号密码'),
                  colorPreset: TButtonColorPreset.primary,
                  variant: TButtonVariant.fill,
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    prefs.setString('SteamPSWD', _passwdController.text);
                    prefs.setString('SteamName', _nameController.text);
                    TToast.showSuccess('保存成功!', context: Get.context!);
                  },
                ),
                SizedBox(width: 16),
                TButton(
                  child: const Text('清除账号密码'),
                  colorPreset: TButtonColorPreset.danger,
                  variant: TButtonVariant.outline,
                  icon: const Icon(Icons.clear),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    prefs.remove("SteamPSWD");
                    prefs.remove("SteamName");
                    setState(() {
                      _nameController.clear();
                      _passwdController.clear();
                    });
                    TToast.showSuccess('已清除!', context: Get.context!);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 修改后的 _buildSoftwareInformation 方法
  Widget _buildSoftwareInformation(String? appVersion) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TButton(
              child: const Text('开源地址'),
              colorPreset: TButtonColorPreset.light,
              variant: TButtonVariant.text,
              icon: const Icon(Icons.link),
              onPressed: () {
                _launchUrl(
                  "https://github.com/user1121114685/Wallpaper_Engine",
                );
              },
            ),
            Text(
              appVersion != null ? '软件版本: $appVersion' : '软件版本: 加载中...',
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.download, color: context.tTheme.brandColor7),
                SizedBox(width: 8),
                Text(
                  '下载壁纸',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.tTheme.textColorPrimary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: TInput(
                    controller: urlController,
                    hintText:
                        '例如: https://steamcommunity.com/sharedfiles/filedetails/?id=1289832516',
                    prefix: const Icon(Icons.link),
                    maxLines: 1,
                    onEditingComplete: () {
                      _handleDownload();
                    },
                  ),
                ),
                SizedBox(width: 16),
                TButton(
                  child: const Text('下载'),
                  colorPreset: TButtonColorPreset.primary,
                  variant: TButtonVariant.fill,
                  icon: const Icon(Icons.download),
                  size: TButtonSize.large,
                  onPressed: _handleDownload,
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '整页下载',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: context.tTheme.textColorPrimary,
                  ),
                ),
                SizedBox(width: 8),
                TSwitch(
                  value: multidown,
                  onChanged: (value) {
                    setState(() {
                      multidown = value;
                    });
                  },
                ),
                SizedBox(width: 24),
                TTag(
                  multidown ? '整页模式' : '单个模式',
                  colorPreset: multidown
                      ? TTagColorPreset.primary
                      : TTagColorPreset.defaultTheme,
                  variant: TTagVariant.light,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogSection() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.chat, color: context.tTheme.brandColor7),
                SizedBox(width: 8),
                Text(
                  '运行日志',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.tTheme.textColorPrimary,
                  ),
                ),
                Spacer(),
                TButton(
                  child: const Text('清空日志'),
                  colorPreset: TButtonColorPreset.light,
                  variant: TButtonVariant.text,
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      logText.clear();
                      logsNotifier.value = "";
                    });
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.tTheme.grayColor3),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(20),
              child: ValueListenableBuilder(
                valueListenable: logsNotifier,
                builder: (context, value, child) {
                  return ListView.separated(
                    itemCount: logText.length,
                    separatorBuilder: (context, index) => SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      return Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: index == 0
                              ? context.tTheme.brandColor1
                              : context.tTheme.grayColor2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          logText[index],
                          style: TextStyle(
                            fontSize: 12,
                            color: index == 0
                                ? context.tTheme.brandColor7
                                : context.tTheme.textColorSecondary,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Divider(height: 1, color: context.tTheme.grayColor3),
          ValueListenableBuilder<bool>(
            valueListenable: _steamCmdRunning,
            builder: (context, running, child) => ValueListenableBuilder<bool>(
              valueListenable: _steamCmdInputReady,
              builder: (context, inputReady, child) => SteamGuardInput(
                enabled: inputReady,
                stopEnabled: running,
                onSend: _sendSteamGuardCode,
                onStop: _stopSteamCmd,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleDownload() {
    if (_steamCmdRunning.value) {
      TToast.showFail('SteamCMD 正在运行', context: context);
      return;
    }
    RegExp exp = RegExp(r"id=\d+");
    var fileid = exp.stringMatch(urlController.text);

    if (fileid == null) {
      urlController.clear();
      logTextAdd("请输入正确的ID,连接包含id=xxxxxx");
      TToast.showFail('连接有误！', context: context);
    } else {
      if (multidown) {
        multiDownFile();
      } else {
        logTextAdd("ID正确  开始下载...");
        toDownItem(fileid);
        // toDownItemProcessStart(fileid!);
      }
    }
  }

  @override
  void dispose() {
    urlController.dispose();
    _nameController.dispose();
    _passwdController.dispose();
    super.dispose();
  }
}

void _launchUrl(String urlString) async {
  var url = Uri.parse(urlString);
  if (!await launchUrl(url)) throw 'Could not launch $url';
}

Future<void> _sendSteamGuardCode(String code) async {
  final session = _activeSteamCmd;
  if (session == null) return;
  await session.sendInput(code);
  await logTextAdd('Steam Guard 验证码已发送');
}

void _stopSteamCmd() {
  if (_activeSteamCmd?.stop() ?? false) {
    logTextAdd('正在停止 SteamCMD...');
  }
}

Future<bool> _runSteamCmd(List<String> arguments) async {
  if (_activeSteamCmd != null) {
    await logTextAdd('已有 SteamCMD 任务正在运行');
    return false;
  }
  final session = SteamCmdHook(
    onOutput: logSteamCmdOutput,
    onInteractiveReady: (ready) => _steamCmdInputReady.value = ready,
    onComplete: () {
      _steamCmdRunning.value = false;
      _steamCmdInputReady.value = false;
    },
  );
  _activeSteamCmd = session;
  _steamCmdRunning.value = true;
  try {
    final steamCmdPath =
        '${executableDirPath()}\\data\\flutter_assets\\assets\\steamcmd\\steamcmd.exe';
    if (!await session.start(steamCmdPath, arguments)) return false;
    final exitCode = await session.completion;
    finishSteamCmdOutput();
    await logTextAdd('SteamCMD 会话已结束，退出码：$exitCode');
    return exitCode == 0;
  } finally {
    _steamCmdRunning.value = false;
    _steamCmdInputReady.value = false;
    if (identical(_activeSteamCmd, session)) _activeSteamCmd = null;
    await session.dispose();
  }
}

Future<void> toDownItem(String downfileid) async {
  final prefs = await SharedPreferences.getInstance();
  final password = prefs.getString('SteamPSWD');
  final name = prefs.getString('SteamName');
  if (name == null || password == null) {
    await logTextAdd('请先输入 Steam 账号密码，并确认该账号已购买 Wallpaper Engine');
    return;
  }
  if (downfileid.length <= 9) {
    urlController.clear();
    await logTextAdd('请输入正确的 ID，链接需要包含 id=xxxxxx');
    return;
  }

  final id = downfileid.substring(3);
  await doLink(false);
  await logTextAdd('开始下载 $id');
  final completed = await _runSteamCmd([
    '+login',
    name,
    password,
    '+workshop_download_item',
    '431960',
    id,
    '+quit',
  ]);
  urlController.clear();
  if (completed) await logTextAdd('SteamCMD 已正常退出，下载命令已结束：$id');
}

Future<void> multiDownFile() async {
  final response = await Dio().get(urlController.text);
  final ids = RegExp(r'id=\d+')
      .allMatches(response.data.toString())
      .map((match) => match[0]!)
      .where((id) => id.length > 9)
      .toSet()
      .toList();
  if (ids.isEmpty) {
    await logTextAdd('这个页面没有可下载的创意工坊项目');
    return;
  }
  await doLink(false);
  await runScriptDown(ids);
}

Future<void> runScriptDown(List<String> ids) async {
  if (ids.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  final password = prefs.getString('SteamPSWD');
  final name = prefs.getString('SteamName');
  if (name == null || password == null) {
    await logTextAdd('请先输入 Steam 账号密码，并确认该账号已购买 Wallpaper Engine');
    return;
  }
  final runDirectory = Directory.current;
  final file = File(
    '${runDirectory.path}\\down_ids_${DateTime.now().microsecondsSinceEpoch}.txt',
  );
  final commands = ids.map(
    (id) => 'workshop_download_item 431960 ${id.substring(3)}',
  );
  await file.writeAsString('${commands.join('\n')}\n');
  try {
    await logTextAdd('开始整页下载 ${ids.first} 开头的 ${ids.length} 个壁纸');
    await _runSteamCmd([
      '+login',
      name,
      password,
      '+runscript',
      file.path,
      '+quit',
    ]);
  } finally {
    if (await file.exists()) await file.delete();
    urlController.clear();
  }
}
