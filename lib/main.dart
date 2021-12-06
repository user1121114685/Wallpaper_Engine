import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:ffi/ffi.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

typedef GOFunc = ffi.Pointer<Utf8>
    Function(); // 这里调用go 函数 没有传入参数 https://www.kikt.top/posts/flutter/ffi/1-first-party/
typedef GetURL = ffi.Pointer<Utf8> Function(); // 这里是操作的dart的返回接口 调用函数返回 string

//  上面两个必须是同一类型....
// E:\Flutter_project\wallpaper_engine_workshop_downloader\windows\runner\main.cpp 改名字

String VerSion = "0010";
// List LogText = ["版本号:" + VerSion];
/// 第一步 定义 ValueNotifier
List<String> LogText = ["版本号:" + VerSion];

/// 第一步 定义 ValueNotifier
ValueNotifier<String> LogsNotifier = ValueNotifier<String>("");
String ApiURL = "";
bool restartWE = false;
String wallpaper64 = "";
bool autoOpenSteamWorkshop = false;
bool autoReDownFailed = false;
bool autoOpened = false;

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
  @override
  Widget build(BuildContext context) {
    if (autoOpenSteamWorkshop == true && autoOpened == false) {
      launchURL("https://steamworkshopdownloader.io/");
      autoOpened = true;
      delayedSeconds(2).then((value) =>
          launchURL("https://steamcommunity.com/app/431960/workshop/"));
    }
    return Scaffold(
        // appBar: AppBar(
        //   title: const Text("Wallpaper Engine 壁纸一键下载"),
        // ),
        body: Container(
      padding: const EdgeInsets.all(5),
      child: Column(
        // mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            //菜单栏 主要存放菜单数据
            children: [
              TextButton(
                child: const Text("壁纸资源网址"),
                onPressed: () {
                  launchURL("https://steamcommunity.com/app/431960/workshop/");
                },
              ),
              TextButton(
                child: const Text("手动下载壁纸网址"),
                onPressed: () {
                  launchURL("https://steamworkshopdownloader.io/");
                },
              ),
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
                        if (result != null) {
                          if (result.files.single.name.toString() ==
                              "wallpaper64.exe") {
                            // obtain shared preferences
                            final prefs = await SharedPreferences.getInstance();
                            prefs.setString('wallpaper64.exe',
                                result.files.single.path!.toString());

                            setState(() {});
                          }
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
              FutureBuilder(
                future: getAPIforDLL().then((value) {
                  // 得到结果后还是刷新下界面嘛
                  setState(() {});
                }),
                // initialData: const Text("正在获取API"),
                builder: (BuildContext context, AsyncSnapshot snapshot) {
                  // snapshot 接收 future 返回的值
                  return TextButton.icon(
                      onPressed: () async {
                        if (snapshot.data.toString() == "未安装Chrome") {
                          launchURL("https://www.iplaysoft.com/tools/chrome/");
                        }

                        //https://www.iplaysoft.com/tools/chrome/
                        setState(() {});
                      },
                      icon: const Icon(Icons.laptop_chromebook),
                      label: Text(snapshot.data.toString() != "未安装Chrome"
                          ? "已安装Chrome"
                          : "已安装Chrome")); //此处是三元运算。
                },
              ),
            ],
          ),
          Row(
            children: [
              ElevatedButton.icon(
                  onPressed: () {
                    launchURL("https://shaoxia.xyz/");
                  },
                  icon: Icon(Icons.access_alarm_outlined),
                  label: Text("关于作者")),
              const SizedBox(
                width: 5,
              ),
              ElevatedButton.icon(
                  onPressed: () {
                    launchURL(
                        "https://github.com/user1121114685/Wallpaper_Engine");
                    // // getAPIforDLL();
                    // setState(() {});
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text("开源地址")),
              const SizedBox(
                width: 5,
              ),
              ElevatedButton.icon(
                  onPressed: () {
                    ApiURL = "";
                    getAPIforDLL();
                    setState(() {});
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("重获api"))
            ],
          ),
          Row(
            children: [
              const Text("自动打开壁纸资源网址"),
              FutureBuilder(
                future: getCheckBoxValue("autoOpenSteamWorkshop"),
                // initialData: InitialData,
                builder: (BuildContext context, AsyncSnapshot snapshot) {
                  // snapshot 接收 future 返回的值
                  return Checkbox(
                      value: snapshot.data ?? false,
                      onChanged: (i) async {
                        // obtain shared preferences
                        final prefs = await SharedPreferences.getInstance();
                        prefs.setBool('autoOpenSteamWorkshop', i!);
                        setState(() {});
                      });
                },
              ),
              const SizedBox(
                width: 5,
              ),
              const Text("自动重启Wallpaper Engine"),
              FutureBuilder(
                future: getCheckBoxValue("reStartWE"),
                // initialData: InitialData,
                builder: (BuildContext context, AsyncSnapshot snapshot) {
                  // snapshot 接收 future 返回的值
                  return Checkbox(
                      value: snapshot.data ?? false,
                      onChanged: (i) async {
                        // obtain shared preferences
                        final prefs = await SharedPreferences.getInstance();
                        prefs.setBool('reStartWE', i!);
                        setState(() {});
                      });
                },
              ),
              // SizedBox(
              //   width: 5,
              // ),
              // Text("失败自动重下"),
              // FutureBuilder(
              //   future: getCheckBoxValue("autoReDownFailed"),
              //   // initialData: InitialData,
              //   builder: (BuildContext context, AsyncSnapshot snapshot) {
              //     // snapshot 接收 future 返回的值
              //     return Checkbox(
              //         value: snapshot.data ?? false,
              //         onChanged: (i) async {
              //           // obtain shared preferences
              //           final prefs = await SharedPreferences.getInstance();
              //           prefs.setBool('autoReDownFailed', i!);
              //           setState(() {});
              //         });
              //   },
              // ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: 600,
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

                      downlaodAndUnzip(fileid.toString());
                    }
                  },
                  decoration: const InputDecoration(
                      labelText: "输入下载地址(包含id=xxxxxxxx)",
                      hintText:
                          " 例如 https://steamcommunity.com/sharedfiles/filedetails/?id=1289832516"),
                ),
              ),
              SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                      onPressed: () {
                        RegExp exp = RegExp(r"id=\d+");
                        var fileid = exp.stringMatch(urlController.text);

                        if (fileid == null) {
                          urlController.clear();
                          logTextAdd("请输入正确的ID,连接包含id=xxxxxx");
                        } else {
                          fileid = fileid.substring(3);
                          logTextAdd("ID正确  开始下载...");

                          downlaodAndUnzip(fileid.toString());
                        }
                      },
                      icon: const Icon(Icons.download),
                      label: const Text("下载壁纸"))),
            ],
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

Future getCheckBoxValue(String keyword) async {
  final prefs = await SharedPreferences.getInstance();
  if (keyword == "reStartWE") {
    restartWE = prefs.getBool(keyword)!;
  }
// Try reading data from the counter key. If it doesn't exist, return 0.
  if (keyword == "autoOpenSteamWorkshop") {
    autoOpenSteamWorkshop = prefs.getBool(keyword)!;
  }
  //autoReDownFailed
  if (keyword == "autoReDownFailed") {
    autoReDownFailed = prefs.getBool(keyword)!;
  }
  return prefs.getBool(keyword);
}

void launchURL(String url) async =>
    await canLaunch(url) ? await launch(url) : throw 'Could not launch $url';

// Future getAPIurl() async {
//   Directory tempDir = await getTemporaryDirectory();
//   String tempPath = tempDir.path;
//   print(tempPath);
//   await Process.run(
//       "E:\\Flutter_project\\wallpaper_engine_workshop_downloader\\lib\\API\\steamdownload.exe",
//       []).then((value) async {
//     try {
//       var resp = await Dio().get("http://127.0.0.1:9191/api");
//       logTextAdd(resp.toString());

//       ApiURL = resp.toString();
//     } catch (e) {
//       print(e);
//     }
//   });

//   print(LogText);
// }

Future getAPIforDLL() async {
  if (ApiURL == "") {
    var dll = ffi.DynamicLibrary.open(
        r'data/flutter_assets/assets/steamdownload.dll');
    // 下面是调试代码
    //     var dll = ffi.DynamicLibrary.open(
    // r'assets/steamdownload.dll');
// 把我弄不会了，日了。。。。 看来只能修改pubspec.yaml 这样与实际的不一致的地方了
// 你以为我想放这里吗？编译的时候直接放进去了。。。data\flutter_assets\assets\steamdownload.dll
    // https://www.coder.work/article/7192255 重要得参考 FFI得使用
    // GOLANG中 导出的函数要首字大写 getAPI是错的 并且还需加上注释 //export GetAPI
    final GetURL geturl =
        dll.lookup<ffi.NativeFunction<GOFunc>>('GetAPI').asFunction();
    var url = geturl();

    logTextAdd("找到了API    " + url.cast<Utf8>().toDartString());
    if (url.cast<Utf8>().toDartString() != "未安装Chrome") {
      ApiURL = url.cast<Utf8>().toDartString();
    }

    return url.cast<Utf8>().toDartString();
  }
}

Future downlaodAndUnzip(String fileid) async {
  // String wallpaper64 = getPreferences("wallpaper64.exe").toString();
  if (wallpaper64 != "null") {
    try {
      // 向服务器发送下载请求  常量与变量才使用+连接，常量与常量可以直接连接
// https://node04.steamworkshopdownloader.io/prod/api/download/request
      // {"publishedFileId":2672939813,"collectionId":null,"hidden":false,"downloadFormat":"raw","autodownload":false}
      // List<int> byte = utf8.encode();
      Map idmap = {
        "publishedFileId": fileid,
        "collectionId": "null",
        "hidden": "false",
        "downloadFormat": "raw",
        "autodownload": "false"
      };

      var postData = "{\"publishedFileId\":" +
          fileid +
          ",\"collectionId\":null,\"hidden\":false,\"downloadFormat\":raw,\"autodownload\":false}";
      var body = json.encode(postData);

      // var resp = await Dio().post(ApiURL + "download/request",
      //     data: Stream.value(idmap),
      //     options: Options(
      //         headers: {"content-type": "application/x-www-form-urlencoded"}));

      // var request =
      //     http.Request('POST', Uri.parse(ApiURL + "download/request"));
      // request.body = "{\"publishedFileId\":" +
      //     fileid +
      //     ",\"collectionId\":null,\"hidden\":false,\"downloadFormat\":raw,\"autodownload\":false}";
      // 得到返回的UUID
// {"uuid":"07e15f2f-c4e2-44f3-a424-f367f1d3c961"}
// {"uuid":"7d866a3d-c948-4c3d-a940-40ef36a6580c"}

      var response =
          await http.post(Uri.parse(ApiURL + "download/request"), body: body);

      Map<String, dynamic> uuid =
          jsonDecode(response.body); // 简单的序列化下返回的Json 关键点为 索引的UUID 为string
      //resp.data["uuid"];
      String newuuid = uuid["uuid"];
      //查询服务器下载状态
      bool addProgress = false;
      while (true) {
        try {
          Response status = await Dio().post(ApiURL + "download/status",
              data: "{\"uuids\":[\"" + newuuid + "\"]}");
          // 返回下载进度
          //{"07e15f2f-c4e2-44f3-a424-f367f1d3c961":{"age":6,"status":"retrieved","progress":100,"progressText":"retrieving: 100%","downloadError":"never transmitted"}}
          Map<String, dynamic> serverStatus = jsonDecode(status.data);
          // print(serverStatus[newuuid]["progressText"]);

          if (serverStatus[newuuid]["progressText"]
              .toString()
              .contains("failed")) {
            //包含 failed 下载失败
            logTextAdd(fileid + "  下载失败");

            break;
          }
          // print("object");
          // print("下载进度" + serverStatus[newuuid]["progress"]);
          if (serverStatus[newuuid]["progress"] > 150) {
            logTextAdd(fileid + "  服务器下载成功...开始下载到本地");
            break;
          }
          // 还是为了直观好看 只显示一行log
          if (addProgress == false) {
            logTextAdd(fileid +
                "  服务器下载进度" +
                serverStatus[newuuid]["progress"].toString() +
                "%");
            addProgress = true;
          } else {
            String log = fileid +
                "  服务器下载进度" +
                serverStatus[newuuid]["progress"].toString() +
                "%";
            LogText[0] = log;
            LogsNotifier.value = log;
          }
        } catch (e) {
          logTextAdd("服务器下载错误  " + e.toString());
        }
        await delayedSeconds(1);
      }
      // 获取下载路径
      String dlDir = await getPreferences("wallpaper64.exe");
      dlDir = dlDir.replaceAll("wallpaper64.exe", "");
      // 文件下载信息
// https://node03.steamworkshopdownloader.io/prod/api/details/file
// 存放 文件大小
      String fileSize = "";
      try {
        Response detail =
            await Dio().post(ApiURL + "details/file", data: "[" + fileid + "]");
        List<dynamic> fileDetails = jsonDecode(detail.data);
        fileSize = fileDetails[0]["file_size"].toString();
        if (fileSize != "") {
          fileSize =
              "/" + (int.parse(fileSize) / 1048576).toStringAsFixed(2) + "M";
        }
      } catch (e) {
        logTextAdd("获取文件信息错误  " + e.toString());
      }

// 是否已经单独添加一行log?
      bool addDownloadlog = false;
      await downloadWithAria2(
          ApiURL + "download/transmit?uuid=" + newuuid, fileid, dlDir);
      // await Dio().download(
      //     ApiURL + "download/transmit?uuid=" + newuuid, dlDir + fileid + ".zip",
      //     // options: Options(//下载提速尝试
      //     //     headers: {
      //     //   "referer": "https://steamworkshopdownloader.io",
      //     //   "sec-ch-ua-platform": "\"Windows\"",
      //     //   "sec-ch-ua-mobile": "?0",
      //     //   "Cookie":
      //     //       "_ga=GA1.2.1102444544.1607616183; __gads=ID=7021e42601a47098-2226edcc41c50074:T=1607616184:RT=1607616184:S=ALNI_MYHNpqo-R1v2yp7NzmSs0cdEGCKAQ; usprivacy=1YNN; _gid=GA1.2.2059147179.1637834067; cto_bundle=1GLoHl9MWFFzUWh4UXlZVDlwbWRITGJsajBqSVZwJTJGRU5pY0lCd0JXb1d1a1dtS05zY2tXc0k3N1M5OXBwVDA1cWRBR2dRTVBuV2xyUnkwdSUyRjRhWmZFR2FzVHlvNElCaVhUektiVllZSG56c3k2SldFVjZ1OVVVT3FSOTdXZE91U1Y5cG9Ia1FBOGdUYWk2QkNmJTJCUTZPODRwd3NNbEJnNGY4Q0p3UFJCbE56UXhKJTJGdyUzRA; _gat=1",
      //     //   "upgrade-insecure-requests": "1",
      //     //   "dnt": "1",
      //     //   "sec-fetch-site": "same-site",
      //     //   "sec-fetch-mode": "navigate",
      //     //   "sec-fetch-user": "?1",
      //     //   "sec-fetch-dest": "document",
      //     //   "sec-ch-ua":
      //     //       "\" Not A;Brand\";v=\"99\", \"Chromium\";v=\"96\", \"Google Chrome\";v=\"96\"",
      //     //   "user-agent":
      //     //       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36"
      //     // }),
      //     onReceiveProgress: (int cont, int _) {
      //   if (addDownloadlog == true) {
      //     String log = fileid +
      //         " 已下载  " +
      //         (cont / 1048576).toStringAsFixed(2) +
      //         "M" +
      //         fileSize;
      //     LogText[0] = log;
      //     LogsNotifier.value = log;
      //   } else {
      //     logTextAdd(fileid +
      //         " 已下载  " +
      //         (cont / 1048576).toStringAsFixed(2) +
      //         "M" +
      //         fileSize);
      //     addDownloadlog = true;
      //   }
      // });

      logTextAdd("下载完成开始解压.....");
      // 解压文件
      // Read the Zip file from disk.
      final bytes = File(dlDir + fileid + ".zip").readAsBytesSync();

      // Decode the Zip file
      final archive = ZipDecoder().decodeBytes(bytes);

      // Extract the contents of the Zip archive to disk.
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          logTextAdd(
              "正在解压  /projects/defaultprojects/" + fileid + "/" + filename);
          final data = file.content as List<int>;
          File(dlDir + "/projects/defaultprojects/" + fileid + "/" + filename)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory(dlDir +
                  "/projects/defaultprojects/" +
                  fileid +
                  "/" +
                  filename)
              .create(recursive: true);
        }
      }
      logTextAdd("已解压完成.....");
      //清空输入框
      urlController.clear();
      // 删除临时文件
      File tmpFile = File(dlDir + fileid + ".zip");
      tmpFile.deleteSync();
      // 重启 we软件

      if (restartWE == true) {
        Process.run("taskkill", ["/F", "/IM", "wallpaper64.exe"])
            .then((s) async {
          await Process.run(wallpaper64, []);
          await delayedSeconds(2).then((value) async {
            await Process.run(wallpaper64, []);
          });
        });
      }
    } catch (e) {}
  } else {
    logTextAdd("请先选择wallpaper64.exe");
  }
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

Future downloadWithAria2(String url, String fileID, String dlDIR) async {
  await Process.run(r'data/flutter_assets/assets/aria2c.exe',
      [url, "-o " + dlDIR + fileID + ".zip"]).then((value) => print("下载成功"));
  await Process.run(wallpaper64, []);
}
