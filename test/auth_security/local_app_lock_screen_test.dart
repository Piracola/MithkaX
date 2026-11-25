import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/security/local_app_lock_controller.dart';
import 'package:mithka/security/local_app_lock_views.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('lock screen shows the emblem, glass keypad and brand footer', (
    tester,
  ) async {
    await _pumpLock(tester);
    expect(find.text('Unlock Mithka X'), findsOneWidget);
    expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
    for (final digit in const [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
    ]) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(find.text('Mithka X'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong PIN shakes the identity cluster and reports inline', (
    tester,
  ) async {
    final harness = await _pumpLock(tester);
    for (var index = 0; index < 4; index += 1) {
      await tester.tap(find.text('9'));
      await tester.pump();
    }
    await _drainHash(tester, harness);
    expect(find.text('That PIN is not correct.'), findsOneWidget);
    expect(harness.controller.locked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the gate fits a small phone by scrolling, not overflowing', (
    tester,
  ) async {
    await _pumpLock(tester, size: const Size(360, 640));
    expect(find.text('Enter your 4-digit PIN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-lock settings offer and persist the immediate option', (
    tester,
  ) async {
    final harness = await _pumpLockSettings(tester);
    await tester.tap(find.text('Auto-Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Immediately'), findsOneWidget);

    await tester.tap(find.text('Immediately'));
    await tester.pumpAndSettle();

    expect(
      harness.controller.autoLockOption,
      AppLockAutoLockOption.immediately,
    );
    expect(find.text('Immediately'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _drainHash(WidgetTester tester, _LockHarness harness) async {
  for (
    var attempt = 0;
    attempt < 100 && harness.controller.locked;
    attempt += 1
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _LockHarness {
  _LockHarness({
    required this.controller,
    required this.theme,
    required this.storage,
  });

  final LocalAppLockController controller;
  final ThemeController theme;
  final Map<String, String> storage;
}

Future<_LockHarness> _pumpLock(
  WidgetTester tester, {
  Size size = const Size(430, 932),
}) async {
  final harness = await _createHarness(tester, size);
  await tester.runAsync(() async {
    await harness.controller.initialize();
    await harness.controller.setCredential(AppLockCredentialType.pin, '2468');
    harness.controller.lock();
  });
  await tester.pumpWidget(_harnessApp(const LocalAppLockGate(), harness));
  await tester.pumpAndSettle();
  return harness;
}

Future<_LockHarness> _pumpLockSettings(WidgetTester tester) async {
  final harness = await _createHarness(tester, const Size(900, 1200));
  await tester.runAsync(() async {
    await harness.controller.initialize();
    await harness.controller.setCredential(AppLockCredentialType.pin, '2468');
  });
  await tester.pumpWidget(_harnessApp(const AppLockSettingsView(), harness));
  await tester.pumpAndSettle();
  return harness;
}

Future<_LockHarness> _createHarness(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);

  final storage = <String, String>{};
  final controller = LocalAppLockController(
    secureRead: (key) async => storage[key],
    secureWrite: (key, value) async {
      if (value == null) {
        storage.remove(key);
      } else {
        storage[key] = value;
      }
    },
    privacyShieldApply: (_) async {},
    platformSupportsBiometrics: false,
    hashRounds: 4,
  );
  addTearDown(controller.dispose);
  return _LockHarness(controller: controller, theme: theme, storage: storage);
}

Widget _harnessApp(Widget home, _LockHarness harness) => MultiProvider(
  providers: [
    ChangeNotifierProvider<ThemeController>.value(value: harness.theme),
    ChangeNotifierProvider<LocalAppLockController>.value(
      value: harness.controller,
    ),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);
