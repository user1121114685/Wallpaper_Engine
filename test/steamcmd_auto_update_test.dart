import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_engine_workshop_downloader/steamcmd_ffi.dart';

final _NativeTestArtifacts? _nativeArtifacts = _findNativeTestArtifacts();

_NativeTestArtifacts? _findNativeTestArtifacts() {
  final root = Directory.current.path;
  final environment = Platform.environment;
  final stage = Directory(
    environment['STEAMCMD_HOOK_TEST_STAGE'] ?? '$root\\hook\\build\\stage',
  );
  final build = Directory(
    environment['STEAMCMD_HOOK_TEST_BUILD'] ??
        '$root\\hook\\build\\native\\Release',
  );
  final files = [
    File('${stage.path}\\steamcmd_worker.exe'),
    File('${stage.path}\\steamcmd_hook.dll'),
    File('${build.path}\\steamcmd_fixture.exe'),
  ];
  if (files.any((file) => !file.existsSync())) return null;
  return _NativeTestArtifacts(files);
}

class _NativeTestArtifacts {
  _NativeTestArtifacts(this.files);

  final List<File> files;
}

void main() {
  test(
    'x64 SteamCMD output and child-process guard input reach the log session',
    () async {
      final artifacts = _nativeArtifacts!.files;
      final workspace = await Directory.systemTemp.createTemp(
        'steamcmd-x64-hook-test-',
      );
      final steamCmd = File('${workspace.path}\\steamcmd.exe');
      SteamCmdHook? session;
      final transcript = StringBuffer();
      final codeSent = Completer<void>();
      var sent = false;

      Future<void> onOutput(String output) async {
        transcript.write(output);
        if (!sent && output.contains('Steam Guard code: ')) {
          sent = true;
          try {
            await session!.sendInput('AB12C');
            codeSent.complete();
          } catch (error, stackTrace) {
            codeSent.completeError(error, stackTrace);
          }
        }
      }

      try {
        await artifacts[2].copy(steamCmd.path);
        await artifacts[0].copy('${workspace.path}\\steamcmd_worker.exe');
        await artifacts[1].copy('${workspace.path}\\steamcmd_hook.dll');

        session = SteamCmdHook(
          workerDirectory: workspace,
          onOutput: (output) => unawaited(onOutput(output)),
        );
        expect(await session.start(steamCmd.path, const []), isTrue);
        expect(
          await session.completion.timeout(const Duration(seconds: 25)),
          0,
        );
        await codeSent.future.timeout(const Duration(seconds: 10));
        expect(await is64BitSteamCmd(steamCmd), isTrue);
        final output = transcript.toString();
        expect(output, contains('Steam Guard code: '));
        expect(output, contains('[fixture] ANSI log: 验证码处理通过'));
        expect(
          output,
          contains('[fixture] input received after child relaunch: AB12C'),
        );
        expect(
          output.split('[hook] attached to SteamCMD process').length - 1,
          greaterThanOrEqualTo(2),
        );
      } finally {
        if (session?.isRunning ?? false) {
          session!.stop();
          await session.completion.timeout(const Duration(seconds: 5));
        }
        await session?.dispose();
        await workspace.delete(recursive: true);
      }
    },
    skip: _nativeArtifacts == null
        ? 'Build the x64 hook worker to run the native integration test.'
        : false,
  );
}
