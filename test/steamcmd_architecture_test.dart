import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_engine_workshop_downloader/steamcmd_ffi.dart';

Future<File> _executableWithMachineType(int machineType) async {
  final file = File(
    '${Directory.systemTemp.path}\\steamcmd-pe-$machineType-${DateTime.now().microsecondsSinceEpoch}.exe',
  );
  final bytes = Uint8List(0x200);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0x3c, 0x80, Endian.little);
  header.setUint16(0x80, 0x00004550, Endian.little);
  header.setUint16(0x84, machineType, Endian.little);
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  test('recognizes x64 SteamCMD and rejects 32-bit builds', () async {
    final x86 = await _executableWithMachineType(0x014c);
    final x64 = await _executableWithMachineType(0x8664);
    try {
      expect(await is64BitSteamCmd(x86), false);
      expect(await is64BitSteamCmd(x64), true);
      final output = <String>[];
      final session = SteamCmdHook(
        workerDirectory: Directory.systemTemp,
        onOutput: output.add,
      );
      expect(await session.start(x86.path, const []), false);
      expect(output.join(), contains('supports 64-bit SteamCMD only'));
    } finally {
      await x86.delete();
      await x64.delete();
    }
  });

  test('rejects executables with an unsupported architecture', () async {
    final unsupported = await _executableWithMachineType(0xaa64);
    try {
      await expectLater(
        is64BitSteamCmd(unsupported),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await unsupported.delete();
    }
  });
}
