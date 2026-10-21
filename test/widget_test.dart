import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_engine_workshop_downloader/steam_guard_input.dart';

void main() {
  testWidgets('Steam Guard codes reach the active SteamCMD session', (
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

    await tester.enterText(find.byKey(const Key('steam-guard-code')), 'AB12C');
    await tester.tap(find.byKey(const Key('send-steam-guard-code')));
    await tester.pumpAndSettle();

    expect(submitted, ['AB12C']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
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
          .widget<IconButton>(find.byKey(const Key('send-steam-guard-code')))
          .onPressed,
      isNull,
    );
  });
}
