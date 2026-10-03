import 'package:bombario/main.dart';
import 'package:bombario/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home screen shows solo, online and Wi-Fi options', (
    tester,
  ) async {
    await tester.pumpWidget(const BombarioApp());
    expect(find.text('Bombario'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Host Wi-Fi room'), findsOneWidget);
  });

  testWidgets('online screen offers create and join by code', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const BombarioApp());
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    expect(find.text('Create room'), findsOneWidget);
    expect(find.byKey(const Key('online-code')), findsOneWidget);

    // A short code is caught before any network call.
    await tester.enterText(find.byKey(const Key('online-code')), 'ab1');
    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(find.text('Room codes are 6 letters and digits'), findsOneWidget);
  });

  testWidgets('settings change and achievements list', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettings.memory();
    await tester.pumpWidget(BombarioApp(settings: settings));
    await tester.tap(find.byKey(const Key('settings')));
    await tester.pumpAndSettle();
    expect(settings.leftHanded, isFalse);
    await tester.tap(find.byKey(const Key('left-handed')));
    await tester.pump();
    expect(settings.leftHanded, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Awards'));
    await tester.pumpAndSettle();
    expect(find.text('First Spark'), findsOneWidget);
    expect(find.text('Bombs placed'), findsOneWidget);
  });
}
