import 'dart:io';

import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:dio/dio.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:process_run/shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tdesign_flutter/tdesign_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallpaper_engine_workshop_downloader/utils.dart';

Future main() async {
  runApp(const MyApp());
}

bool multidown = false;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late TDThemeData _themeData;

  @override
  void initState() {
    super.initState();
    _themeData = TDThemeData.defaultData();
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Wallpaper Engine 下载器',
      theme: ThemeData(
        extensions: [_themeData],
        colorScheme: ColorScheme.light(primary: _themeData.brandNormalColor),
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
    _initLogSystem();
  }

  void _initLogSystem() async {
    String path = executableDirPath();
    String logFile =
        "$path\\data\\flutter_assets\\assets\\steamcmd\\logs\\console_log.txt";
    File file = File(logFile);

    LogWatcher(file).startWatching();
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
      backgroundColor: TDTheme.of(context).grayColor1,
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCredentialsSection(context),
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

  Widget _buildFileSelectionSection(BuildContext tDContext) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(TDIcons.folder, color: TDTheme.of(context).brandColor7),
            SizedBox(width: 8),
            Text(
              '壁纸路径设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: TDTheme.of(context).fontGyColor1,
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
                TDTag(
                  hasPath ? "已选择 wallpaper64.exe" : "未选择 wallpaper64.exe",
                  theme: hasPath ? TDTagTheme.success : TDTagTheme.warning,
                  // variant: TDTagVariant.light,
                  icon: hasPath ? TDIcons.check_circle : TDIcons.close_circle,
                ),
                SizedBox(width: 16),
                TDButton(
                  text: '选择文件',
                  theme: TDButtonTheme.primary,
                  type: TDButtonType.outline,
                  icon: TDIcons.browse,
                  onTap: () async {
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
                      TDToast.showSuccess('文件选择成功!', context: tDContext);
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

  Widget _buildCredentialsSection(BuildContext tDContext) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFileSelectionSection(tDContext),
            Row(
              children: [
                Icon(TDIcons.user, color: TDTheme.of(context).brandColor7),
                SizedBox(width: 8),
                Text(
                  'Steam 账号设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: TDTheme.of(context).fontGyColor1,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: TDInput(
                    leftLabel: '账号',
                    controller: _nameController,
                    hintText: '请输入Steam账号',
                    type: TDInputType.normal,
                  ),
                ),
                SizedBox(width: 16),
                Flexible(
                  child: TDInput(
                    leftLabel: '密码',
                    controller: _passwdController,
                    hintText: '请输入Steam密码',
                    type: TDInputType.normal,
                    obscureText: !_isPasswordVisible,
                    rightBtn: TDButton(
                      icon: _isPasswordVisible
                          ? TDIcons.browse_off
                          : TDIcons.browse,
                      onTap: () {
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
                TDButton(
                  text: '保存账号密码',
                  theme: TDButtonTheme.primary,
                  type: TDButtonType.fill,
                  icon: TDIcons.save,
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    prefs.setString('SteamPSWD', _passwdController.text);
                    prefs.setString('SteamName', _nameController.text);
                    TDToast.showSuccess('保存成功!', context: tDContext);
                  },
                ),
                SizedBox(width: 16),
                TDButton(
                  text: '清除账号密码',
                  theme: TDButtonTheme.danger,
                  type: TDButtonType.outline,
                  icon: TDIcons.clear,
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    prefs.remove("SteamPSWD");
                    prefs.remove("SteamName");
                    setState(() {
                      _nameController.clear();
                      _passwdController.clear();
                    });
                    TDToast.showSuccess('已清除!', context: tDContext);
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
            TDButton(
              text: '开源地址',
              theme: TDButtonTheme.light,
              type: TDButtonType.text,
              icon: TDIcons.link,
              onTap: () {
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
                Icon(TDIcons.download, color: TDTheme.of(context).brandColor7),
                SizedBox(width: 8),
                Text(
                  '下载壁纸',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: TDTheme.of(context).fontGyColor1,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Flexible(
                  child: TDInput(
                    controller: urlController,
                    hintText:
                        '例如: https://steamcommunity.com/sharedfiles/filedetails/?id=1289832516',
                    type: TDInputType.normal,
                    leftIcon: Icon(TDIcons.link),
                    maxLines: 1,
                    onEditingComplete: () {
                      _handleDownload();
                    },
                  ),
                ),
                SizedBox(width: 16),
                TDButton(
                  text: '下载',
                  theme: TDButtonTheme.primary,
                  type: TDButtonType.fill,
                  icon: TDIcons.download,
                  size: TDButtonSize.large,
                  onTap: _handleDownload,
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
                    color: TDTheme.of(context).fontGyColor1,
                  ),
                ),
                SizedBox(width: 8),
                TDSwitch(
                  isOn: multidown,
                  onChanged: (value) {
                    setState(() {
                      multidown = value;
                    });
                    return true;
                  },
                ),
                SizedBox(width: 24),
                TDTag(
                  multidown ? '整页模式' : '单个模式',
                  theme: multidown
                      ? TDTagTheme.primary
                      : TDTagTheme.defaultTheme,
                  // variant: TDTagVariant.light,
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
                Icon(TDIcons.chat, color: TDTheme.of(context).brandColor7),
                SizedBox(width: 8),
                Text(
                  '运行日志',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: TDTheme.of(context).fontGyColor1,
                  ),
                ),
                Spacer(),
                TDButton(
                  text: '清空日志',
                  theme: TDButtonTheme.light,
                  type: TDButtonType.text,
                  icon: TDIcons.clear,
                  onTap: () {
                    setState(() {
                      logText.clear();
                      logsNotifier.value = "";
                    });
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: TDTheme.of(context).grayColor3),
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
                              ? TDTheme.of(context).brandColor1
                              : TDTheme.of(context).grayColor2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          logText[index],
                          style: TextStyle(
                            fontSize: 12,
                            color: index == 0
                                ? TDTheme.of(context).brandColor7
                                : TDTheme.of(context).fontGyColor2,
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
        ],
      ),
    );
  }

  void _handleDownload() {
    RegExp exp = RegExp(r"id=\d+");
    var fileid = exp.stringMatch(urlController.text);

    if (fileid == null) {
      urlController.clear();
      logTextAdd("请输入正确的ID,连接包含id=xxxxxx");
      TDToast.showFail('连接有误！', context: context);
    } else {
      fileid = fileid.substring(3);
      logTextAdd("ID正确  开始下载...");

      if (multidown) {
        multiDownFile();
      } else {
        RegExp exp = RegExp(r"id=\d+");
        var fileid = exp.stringMatch(urlController.text);
        toDownItem(fileid!);
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

Future toDownItem(String downfileid) async {
  final prefs = await SharedPreferences.getInstance();
  var passWD = prefs.get("SteamPSWD");
  var name = prefs.get("SteamName");

  if (name != null && passWD != null) {
    if (downfileid == "" || downfileid.length <= 9) {
      urlController.clear();
      logTextAdd("请输入正确的ID,连接包含id=xxxxxx");
    } else {
      downfileid = downfileid.substring(3);
      logTextAdd("ID正确  开始下载...");
      Future downItem() async {
        String executablePath = executableDirPath();

        var script =
            "$executablePath\\data\\flutter_assets\\assets\\steamcmd\\steamcmd.exe +login $name $passWD +workshop_download_item 431960 $downfileid +quit";
        var shell = Shell();
        await shell.run("cmd /c start $script");
      }

      doLink(false).then((value) {
        logTextAdd("开始下载 $downfileid");
        downItem().then((value) {
          urlController.clear();
          logTextAdd("已完成 $downfileid 下载");
        });
      });
    }
  } else {
    logTextAdd("请先输入Steam账号密码，并且该账号已经购买了Wallpaper Engine");
  }
}

Future multiDownFile() async {
  List<String> ids = [];
  Response response;
  var dio = Dio();
  response = await dio.get(urlController.text);
  RegExp exp = RegExp(r"id=\d+");
  var fileids = exp.allMatches(response.data.toString());

  for (Match m in fileids) {
    if (m[0]!.length <= 9) {
      continue;
    }
    ids.add(m[0]!);
    if (kDebugMode) {
      print(m[0]!);
    }
  }

  doLink(false).then((v) {
    runScriptDown(ids);
  });
}

Future runScriptDown(List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  var passWD = prefs.get("SteamPSWD");
  var name = prefs.get("SteamName");
  String runDir = Directory.current.path;
  String path = "$runDir/down_ids.txt";
  File file = File(path);

  Future.forEach(ids, (element) {
    element = element.toString().substring(3);
    file.writeAsStringSync(
      "workshop_download_item 431960 $element\n",
      mode: FileMode.append,
    );
  });

  String executablePath = executableDirPath();
  if (kDebugMode) {
    print('当前正在下载整页文件');
  }
  var script =
      "$executablePath\\data\\flutter_assets\\assets\\steamcmd\\steamcmd.exe +login $name $passWD +runscript $path +quit";
  var shell = Shell();
  await shell
      .run("cmd /c start $script")
      .then((value) => logTextAdd("整页下载已完成....."));
  file.deleteSync();
  urlController.clear();
}
