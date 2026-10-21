import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_engine_workshop_downloader/steam_guard_input.dart';
import 'package:wallpaper_engine_workshop_downloader/utils.dart';

void main() {
  testWidgets('SteamCMD input reaches the active session', (
    WidgetTester tester,
  ) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SteamGuardInput(
            enabled: true,
            stopEnabled: true,
            onSend: (code) async => submitted.add(code),
            onStop: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('steamcmd-input')), 'AB12C');
    await tester.tap(find.byKey(const Key('send-steamcmd-input')));
    await tester.pumpAndSettle();

    expect(submitted, ['AB12C']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('the Steam Guard dialog submits its code', (
    WidgetTester tester,
  ) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SteamGuardCodeDialog(
            onSubmit: (code) async => submitted.add(code),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('steam-guard-dialog-input')),
      'CD34E',
    );
    await tester.tap(find.byKey(const Key('send-steam-guard-dialog-code')));
    await tester.pumpAndSettle();

    expect(submitted, ['CD34E']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  test('Steam Guard prompt detection handles split output', () {
    final detector = SteamGuardPromptDetector();

    expect(detector.add('Login is waiting for input'), isFalse);
    expect(detector.add('Steam Guard co'), isFalse);
    expect(detector.add('de: '), isTrue);
    expect(detector.add('The code was accepted'), isFalse);
    expect(detector.add('steam guard code: '), isTrue);
  });

  test('repeated SteamCMD log output still publishes list updates', () {
    var updateCount = 0;
    void onUpdate() => updateCount++;
    logsNotifier.addListener(onUpdate);
    finishSteamCmdOutput();

    try {
      logSteamCmdOutput('[test] repeated line\n');
      logSteamCmdOutput('[test] repeated line\n');

      expect(updateCount, 2);
      expect(logText.take(2), ['[test] repeated line', '[test] repeated line']);
    } finally {
      logsNotifier.removeListener(onUpdate);
      logText.removeWhere((line) => line == '[test] repeated line');
      finishSteamCmdOutput();
    }
  });

  testWidgets('the code field stays disabled outside an active session', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SteamGuardInput(
            enabled: false,
            stopEnabled: false,
            onSend: (code) async {},
            onStop: () {},
          ),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, false);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('send-steamcmd-input')))
          .onPressed,
      isNull,
    );
  });
}
