import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:process_run/shell.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

Future main() async {
  // await Isolate.spawn((message) {getAPIforDLL();}, num);
  runApp(const MyApp());
}

// steamcmd +login anonymous +force_install_dir c:\steamcmd\csgoserver +app_update 740 validate +quit
// steamcmd +login AA BB +workshop_download_item 221100 1605653648 +quit

//  上面两个必须是同一类型....
// E:\Flutter_project\wallpaper_engine_workshop_downloader\windows\runner\main.cpp 改名字

String VerSion = "V024";
// List LogText = ["版本号:" + VerSion];
/// 第一步 定义 ValueNotifier
List<String> LogText = ["版本号:" + VerSion];

/// 第一步 定义 ValueNotifier
ValueNotifier<String> LogsNotifier = ValueNotifier<String>("");

String wallpaper64 = "";
bool multidown = false;
int i_down_num = 0;
List<String> ids = [];

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // title: "ceui",
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

//定义一个controller
TextEditingController urlController = TextEditingController();

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    _launchUrl("https://steamcommunity.com/app/431960/workshop/");
    return Scaffold(
        body: Container(
      padding: const EdgeInsets.all(15),
      child: Column(
        // mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            //菜单栏 主要存放菜单数据
            children: [
              FutureBuilder(
                future: getPreferences("wallpaper64.exe"),
                // initialData: InitialData,
                builder: (BuildContext context, AsyncSnapshot snapshot) {
                  // snapshot 接收 future 返回的值
                  return TextButton.icon(
                      onPressed: () async {
                        FilePickerResult? result =
                            await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['exe'],
                        );
                        // print(result!.files.single.name.toString());
                        if (result != null &&
                            result.files.single.name.toString() ==
                                "wallpaper64.exe") {
                          // obtain shared preferences
                          final prefs = await SharedPreferences.getInstance();
                          prefs.setString('wallpaper64.exe',
                              result.files.single.path!.toString());
                          // 重新选择 壁纸路径之后重建软连接
                          doLink(true);
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.favorite),
                      label: Text(
                          // 如果字符串中包含了 壁纸路径 就显示已找到
                          snapshot.data.toString().contains("wallpaper64.exe")
                              ? "已选择wallpaper64.exe"
                              : "未选择wallpaper64.exe")); //此处是三元运算。
                },
              ),
              const SizedBox(
                width: 20,
              ),
              ElevatedButton.icon(
                  onPressed: () {
                    _launchUrl(
                        "https://github.com/user1121114685/Wallpaper_Engine");
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text("开源地址")),
              const SizedBox(
                width: 20,
              ),
              // 因为需要建立软连接 所以需要管理员运行
              Text(
                "首次使用 需要以管理员权限运行！",
                style: TextStyle(color: Colors.red[200], fontSize: 23),
              )
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          const Divider(
              // color: Colors.red,
              ),
          Row(
            children: [
              const Text("Steam账号："),
              SizedBox(
                width: 110,
                height: 30,
                child: TextField(
                    controller: _nameController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(width: 2, color: Colors.blue),
                    ))),
              ),
              const Text("Steam密码："),
              SizedBox(
                width: 110,
                height: 30,
                child: TextField(
                    controller: _passwdController,
                    textInputAction: TextInputAction.done,
                    obscureText: true,
                    decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(width: 2, color: Colors.blue),
                    ))),
              ),
              const SizedBox(
                width: 20,
              ),
              ElevatedButton(
                  onPressed: () async {
                    // 将名字保存起来
                    final prefs = await SharedPreferences.getInstance();
                    prefs.setString('SteamPSWD', _passwdController.text);
                    prefs.setString('SteamName', _nameController.text);
                  },
                  child: const Text("保存账号密码")),
              const SizedBox(
                width: 10,
              ),
              ElevatedButton(
                  onPressed: () async {
                    // 将名字保存起来
                    final prefs = await SharedPreferences.getInstance();

                    prefs.remove("SteamPSWD");
                    prefs.remove("SteamName");
                  },
                  child: const Text("清除已保存的账号密码")),
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          const Divider(
              // color: Colors.blue,
              ),
          Row(
            children: [
              SizedBox(
                width: 500,
                child: TextField(
                  autofocus: true,
                  controller: urlController,
                  // 当textInputAction: TextInputAction.done, 输入结束时，启用 onEditingComplete函数
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () {
                    RegExp exp = RegExp(r"id=\d+");
                    var fileid = exp.stringMatch(urlController.text);

                    if (fileid == null) {
                      urlController.clear();
                      logTextAdd("请输入正确的ID,连接包含id=xxxxxx");
                    } else {
                      fileid = fileid.substring(3);
                      logTextAdd("ID正确  开始下载...");

                      // 输入命令
                      // 如果勾选了 整页下载就执行整页下载 否则就下载单个
                      if (multidown) {
                        multiDownFile();
                      } else {
                        RegExp exp = RegExp(r"id=\d+");
                        var fileid = exp.stringMatch(urlController.text);

                        toDownItem(fileid!);
                      }
                    }
                  },
                  decoration: const InputDecoration(
                      labelText: "输入下载地址(包含id=xxxxxxxx)",
                      hintText:
                          " 例如 https://steamcommunity.com/sharedfiles/filedetails/?id=1289832516",
                      hintStyle: TextStyle(fontSize: 15),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(width: 2, color: Colors.blue),
                      )),
                ),
              ),
              const SizedBox(
                width: 20,
              ),
              SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                      onPressed: () async {
                        // 如果勾选了 整页下载就执行整页下载 否则就下载单个
                        if (multidown) {
                          multiDownFile();
                        } else {
                          RegExp exp = RegExp(r"id=\d+");
                          var fileid = exp.stringMatch(urlController.text);

                          toDownItem(fileid!);
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text("下载"))),
              const SizedBox(
                width: 20,
              ),
              const Text(
                "整页",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(
                height: 50,
                child: Checkbox(
                    value: multidown,
                    activeColor: Colors.red, //选中时的颜色
                    onChanged: (value) {
                      multidown = value!;
                      setState(() {
                        // _checkboxSelected=value;
                      });
                    }),
              )
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          ValueListenableBuilder(
              valueListenable: LogsNotifier,
              builder: (context, value, child) {
                return Expanded(
                  child: ListView.builder(
                    itemCount: LogText.length,
                    itemBuilder: (BuildContext context, int index) {
                      return Text(LogText[index]); // 算了 加个P时间 毫无意义
                    },
                  ),
                );
              })
        ],
      ),
    ));
  }
}

Future<String> getPreferences(String keyword) async {
  final prefs = await SharedPreferences.getInstance();

// Try reading data from the counter key. If it doesn't exist, return 0.
  if (keyword == "wallpaper64.exe") {
    wallpaper64 = prefs.getString(keyword).toString();
  }
  return prefs.getString(keyword).toString();
}

Future delayedSeconds(int second) async {
  await Future.delayed(Duration(seconds: second));
}

Future logTextAdd(String log) async {
  //LIST的 修改iterable的内容 是不会改变iterable的对象的
// 所以 Notifier 不能使用LIST
  LogText.insert(0, log);
  LogsNotifier.value = log;
}

void _launchUrl(String url_string) async {
  var url = Uri.parse(url_string);
  if (!await launchUrl(url)) throw 'Could not launch $url';
}

Future doLink(bool relink) async {
  //创建链接 https://www.daimajiaoliu.com/daima/479885188100403
  //Link的参数为该链接的Path，create的参数为链接的目标文件夹
  // 获取应用目录
  // String run_dir = (await getApplicationDocumentsDirectory()).path;
  String run_dir = Directory.current.path;

  String dlDir = await getPreferences("wallpaper64.exe");
  dlDir = dlDir.replaceAll("\\wallpaper64.exe", "");

// 这里有问题 不能判断到底是不是 文件夹 连接同样认定为文件夹
  Future _delDir() async {
    var directory_431960 = Directory(
        "$run_dir\\data\\flutter_assets\\assets\\steamcmd\\steamapps\\workshop\\content\\431960");
    var exists = await directory_431960.exists();
    if (exists == true) {
      // 如果文件夹存在就删除
      logTextAdd("431960文件夹删除中....");
      directory_431960.delete(recursive: true);
    }
  }

  Future _check_431960() async {
    var file_431960 = File(
        "$run_dir\\data\\flutter_assets\\assets\\steamcmd\\steamapps\\workshop\\content\\431960");
    FileSystemEntityType type =
        FileSystemEntity.typeSync(file_431960.path, followLinks: false);

    var exists = await file_431960.exists();
    if (exists == false && type.toString() != "link") {
      logTextAdd("431960 连接不存在....");
      // 如果不存在就创建 连接
      _delDir().then((value) {
        Link("$run_dir\\data\\flutter_assets\\assets\\steamcmd\\steamapps\\workshop\\content\\431960")
            .create("$dlDir\\projects\\defaultprojects\\", recursive: true)
            .then((value) => logTextAdd("431960 连接已建立完毕...."));
      });
    } else {
      // 如果需要重建
      if (relink) {
        // 存在 就删除后重新创建
        logTextAdd("431960连接重建中....");
        file_431960.delete();
      }
    }
  }

  _check_431960(); // 检查连接
}

Future toDownItem(String downfileid) async {
  final prefs = await SharedPreferences.getInstance();

  var passWD = prefs.get("SteamPSWD");
  var name = prefs.get("SteamName");

  if (name != null && passWD != null) {
    // id=431960 长度为9 所以简化代码
    if (downfileid == "" || downfileid.length <= 9) {
      urlController.clear();
      logTextAdd("请输入正确的ID,连接包含id=xxxxxx");
    } else {
      downfileid = downfileid.substring(3);
      logTextAdd("ID正确  开始下载...");
      logTextAdd(
          "首次使用Steam 可能需要验证码验证，提示 Steam Guard code:  如果看见此提示 请查看邮箱验证码输入...");

      Future _downItem() async {
        // 输入命令
        // steamcmd +login 名字 密码 +force_install_dir Z:\ +workshop_download_item 431960 2798955847 +quit
        String run_dir = Directory.current.path;
        var script =
            "$run_dir\\data\\flutter_assets\\assets\\steamcmd\\steamcmd.exe +login $name $passWD +workshop_download_item 431960 $downfileid +quit";
        // var script ="./data/flutter_assets/assets/steamcmd/steamcmd.exe +force_install_dir "+"Z:\\"+" +login "+name.toString()+" "+passWD.toString()+" +workshop_download_item 431960 "+fileid+" +quit";
        var shell = Shell();
        await shell.run("cmd /c start $script");
      }

      doLink(false).then((value) {
        logTextAdd("开始下载 $downfileid");
        _downItem().then((value) {
          urlController.clear();
          logTextAdd("已完成 $downfileid 下载");
          if (ids.isNotEmpty && i_down_num != ids.length - 1) {
            i_down_num++;
            toDownItem(ids[i_down_num]);
          } else {
            ids = [];
            i_down_num = 0;
          }

// 准备做 自动打开 感觉没必要 就删了
        });
      });
    }
  } else {
    logTextAdd("请先输入Steam账号密码，并且该账号已经购买了Wallpaper Engine");
    logTextAdd("请先输入Steam账号密码，并且该账号已经购买了Wallpaper Engine");
    logTextAdd("请先输入Steam账号密码，并且该账号已经购买了Wallpaper Engine");
  }
}

Future multiDownFile() async {
  Response response;
  var dio = Dio();
  response = await dio.get(urlController.text);
  RegExp exp = RegExp(r"id=\d+");
  var fileids = exp.allMatches(response.data.toString());

  for (Match m in fileids) {
    // 因为 allmatch 是 惰性匹配 所以每次只加载第一个就好了
    // id=431960 长度为9 所以简化代码
    if (m[0]!.length <= 9) {
      continue;
    }

    ids.add(m[0]!);
    print(m[0]!);
  }
  if (i_down_num == 0) {
    toDownItem(ids[i_down_num]);
  }
}
