import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class SteamCmdHook {
  SteamCmdHook({
    required this.onOutput,
    this.onInteractiveReady,
    this.onComplete,
    this.workerDirectory,
  });

  final void Function(String output) onOutput;
  final void Function(bool ready)? onInteractiveReady;
  final void Function()? onComplete;
  final Directory? workerDirectory;

  Process? _process;
  StreamSubscription<String>? _stdout;
  StreamSubscription<String>? _stderr;
  Future<int> _completion = Future<int>.value(-1);
  bool _finished = true;
  bool _acceptingInput = false;

  Future<bool> start(String steamCmdPath, List<String> arguments) async {
    if (_process != null) {
      onOutput('[steamcmd] A download session is already running.\n');
      return false;
    }

    final executable = File(steamCmdPath).absolute;
    late bool is64Bit;
    try {
      is64Bit = await is64BitSteamCmd(executable);
    } on Object catch (error) {
      onOutput('[steamcmd] Unable to read the SteamCMD executable: $error\n');
      return false;
    }

    if (!is64Bit) {
      onOutput('[steamcmd] This project supports 64-bit SteamCMD only.\n');
      return false;
    }

    _completion = _runWorker(
      executable,
      arguments,
      acceptsInput: true,
      notifyComplete: true,
    );
    return true;
  }

  Future<int> get completion => _completion;

  bool get isRunning => _process != null && !_finished;

  Future<void> sendInput(String input) async {
    if (!isRunning || !_acceptingInput) {
      throw StateError('SteamCMD is not waiting for interactive input.');
    }
    if (input.isEmpty || input.contains('\n') || input.contains('\r')) {
      throw ArgumentError.value(
        input,
        'input',
        'Enter one nonempty console line.',
      );
    }
    final process = _process!;
    process.stdin.add(utf8.encode('$input\n'));
    await process.stdin.flush();
  }

  bool stop() {
    if (!isRunning) return false;
    return _process!.kill();
  }

  Future<void> dispose() async {
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    _process = null;
  }

  Future<int> _runWorker(
    File executable,
    List<String> arguments, {
    required bool acceptsInput,
    required bool notifyComplete,
  }) async {
    final applicationDirectory =
        workerDirectory?.path ?? File(Platform.resolvedExecutable).parent.path;
    final worker =
        '${Directory(applicationDirectory).path}\\steamcmd_worker.exe';
    _finished = false;
    _acceptingInput = false;

    try {
      final process = await Process.start(
        worker,
        [executable.path, ...arguments],
        workingDirectory: executable.parent.path,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      _process = process;
      _stdout = process.stdout
          .transform<String>(const Utf8Decoder(allowMalformed: true))
          .listen(
            (String output) => onOutput(output),
            onDone: stdoutDone.complete,
            onError: (Object error) {
              onOutput('[steamcmd] stdout error: $error\n');
            },
          );
      _stderr = process.stderr
          .transform<String>(const Utf8Decoder(allowMalformed: true))
          .listen(
            (String output) => onOutput('[steamcmd] $output'),
            onDone: stderrDone.complete,
            onError: (Object error) {
              onOutput('[steamcmd] stderr error: $error\n');
            },
          );
      _acceptingInput = acceptsInput;
      onInteractiveReady?.call(acceptsInput);
      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone.future, stderrDone.future]);
      _process = null;
      _acceptingInput = false;
      onInteractiveReady?.call(false);
      _finished = true;
      if (notifyComplete) onComplete?.call();
      return exitCode;
    } on Object catch (error) {
      _process = null;
      _acceptingInput = false;
      _finished = true;
      onInteractiveReady?.call(false);
      onOutput('[steamcmd] Failed to start the hooked worker: $error\n');
      if (notifyComplete) onComplete?.call();
      return -1;
    }
  }
}

Future<bool> is64BitSteamCmd(File executable) async {
  final file = await executable.open();
  try {
    final dosHeader = await file.read(64);
    if (dosHeader.length < 64) {
      throw const FormatException('Invalid PE header.');
    }
    final peOffset = ByteData.sublistView(
      dosHeader,
    ).getUint32(0x3c, Endian.little);
    if (peOffset < 64 || peOffset > await file.length() - 6) {
      throw const FormatException('Invalid PE header offset.');
    }
    await file.setPosition(peOffset + 4);
    final machine = await file.read(2);
    if (machine.length != 2) {
      throw const FormatException('Invalid PE machine type.');
    }
    return switch (ByteData.sublistView(machine).getUint16(0, Endian.little)) {
      0x014c => false,
      0x8664 => true,
      _ => throw const FormatException('Unsupported SteamCMD architecture.'),
    };
  } finally {
    await file.close();
  }
}
