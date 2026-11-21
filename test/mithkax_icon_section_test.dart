//
//  mithkax_icon_section_test.dart
//
//  Pins MithkaX's own app icons:
//
//  - the two fork marks live in their own picker section ("Mithka X icons"),
//    never in the motif grid, and the gradient mark is what a fresh install
//    ships (Dart selection + the manifest-enabled primordial alias);
//  - every artwork the picker and the native bridges reference exists on
//    disk, at the size its consumer expects (1024 plates, per-density Android
//    layers);
//  - re-selecting the shipped default routes through a manifest-disabled
//    clone, so only the first explicit choice ever force-closes the task.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

const _channel = MethodChannel('mithka/app_icon');

void _mockBridge({String current = 'mithkax_default'}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        return switch (call.method) {
          'isSupported' => true,
          'currentIcon' => current,
          'setIcon' => null,
          _ => throw MissingPluginException(),
        };
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );
}

/// IHDR width/height, so a mis-scaled layer fails here instead of on device.
(int, int) _pngSize(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  final bytes = file.readAsBytesSync();
  expect(bytes.sublist(0, 8), [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ], reason: '$path is not a PNG');
  final header = ByteData.sublistView(bytes, 16, 24);
  return (header.getUint32(0), header.getUint32(4));
}

/// PNG colour type (IHDR byte 25): 2 = RGB (opaque), 6 = RGBA (alpha).
int _pngColorType(String path) => File(path).readAsBytesSync()[25];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => L10nFixtures.load().install());

  group('catalogue', () {
    test('the fork marks form their own section, outside the motif grid', () {
      expect(AppIconVariant.mithkaXSection, [
        AppIconVariant.mithkaxDefault,
        AppIconVariant.mithkaxMonochrome,
      ]);
      for (final variant in AppIconVariant.mithkaXSection) {
        expect(
          AppIconVariant.visibleFree.contains(variant),
          isFalse,
          reason:
              '${variant.key} belongs to the Mithka X section, not the nine '
              'motif icons',
        );
        expect(
          variant.requiresSupporter,
          isFalse,
          reason: 'the fork marks are never Supporter icons',
        );
        expect(
          variant.hasPlate,
          isTrue,
          reason: 'the picker must preview their real background',
        );
      }
    });

    test('every referenced artwork exists at its expected size', () {
      for (final variant in AppIconVariant.values) {
        final light = variant.asset;
        expect(_pngSize(light), (1024, 1024), reason: '${variant.key} plate');
        final dark = variant.darkAsset;
        if (dark != null) {
          expect(_pngSize(dark), (1024, 1024), reason: '${variant.key} dark');
        }
        for (final brightness in Brightness.values) {
          final picker = variant.hasPlate
              ? variant.platedPickerAsset(brightness)
              : variant.pickerAsset;
          expect(
            File(picker).existsSync(),
            isTrue,
            reason: '${variant.key} ($brightness) has no picker art: $picker',
          );
        }
      }
    });

    test('the Android launcher carries both marks at every density', () {
      const densities = {
        'mdpi': 1,
        'hdpi': 1.5,
        'xhdpi': 2,
        'xxhdpi': 3,
        'xxxhdpi': 4,
      };
      for (final name in ['mithkax_default', 'mithkax_monochrome']) {
        for (final entry in densities.entries) {
          final factor = entry.value;
          expect(
            _pngSize(
              'android/app/src/main/res/mipmap-${entry.key}/'
              'ic_launcher_$name.png',
            ),
            ((48 * factor).round(), (48 * factor).round()),
            reason: 'legacy 48dp layer for $name in ${entry.key}',
          );
          final backgroundPath =
              'android/app/src/main/res/mipmap-${entry.key}/'
              'ic_launcher_${name}_background.png';
          expect(
            _pngSize(backgroundPath),
            ((108 * factor).round(), (108 * factor).round()),
            reason: 'adaptive 108dp plate for $name in ${entry.key}',
          );
          expect(
            _pngColorType(backgroundPath),
            2,
            reason: 'the plate layer must be opaque RGB',
          );
          // The mark lives in its OWN layer: Android scales a background layer
          // to the full 108dp and crops it to the visible 72dp window, which
          // rendered the mark 1.5x larger than the picker preview when the flat
          // design sat in the background layer.
          final foregroundPath =
              'android/app/src/main/res/mipmap-${entry.key}/'
              'ic_launcher_${name}_foreground.png';
          expect(
            _pngSize(foregroundPath),
            ((108 * factor).round(), (108 * factor).round()),
            reason: 'adaptive 108dp foreground for $name in ${entry.key}',
          );
          expect(
            _pngColorType(foregroundPath),
            6,
            reason: 'the mark layer must carry alpha',
          );
        }
        final adaptive = File(
          'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_$name.xml',
        ).readAsStringSync();
        expect(
          adaptive.contains(
            '<background android:drawable="@mipmap/ic_launcher_${name}_background" />',
          ),
          isTrue,
          reason: 'the plate is the background layer',
        );
        expect(
          adaptive.contains(
            '<foreground android:drawable="@mipmap/ic_launcher_${name}_foreground" />',
          ),
          isTrue,
          reason: 'the mark is the foreground layer, inside the 72dp safe zone',
        );
      }
    });
  });

  group('controller default', () {
    test('a fresh install selects the Mithka X gradient mark', () async {
      _mockBridge();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppIconController(prefs);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.currentVariant, AppIconVariant.mithkaxDefault);
      expect(
        controller.firstChangePending,
        isTrue,
        reason: 'the shipped default is still live: the one-time note applies',
      );
    });

    test(
      'the native current for the shipped default is mithkax_default',
      () async {
        _mockBridge();
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final controller = AppIconController(prefs);
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(
          controller.firstChangePending,
          isTrue,
          reason:
              'currentIcon equal to the shipped default must not count as '
              'an explicit choice',
        );
        expect(controller.retainedUnknownState, isNull);
      },
    );

    test('the monochrome mark is a normal, free choice', () async {
      _mockBridge();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppIconController(prefs);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(
        controller.availableVariants,
        containsAll(AppIconVariant.mithkaXSection),
        reason: 'both fork marks are offered by the picker',
      );
      expect(controller.isLocked(AppIconVariant.mithkaxMonochrome), isFalse);
      expect(
        await controller.setVariant(AppIconVariant.mithkaxMonochrome),
        isTrue,
      );
      expect(prefs.getString('selected_app_icon'), 'mithkax_monochrome');
    });
  });

  group('native source pins', () {
    final kt = File(
      'android/app/src/main/kotlin/x/empty/mithka/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('the shipped launcher alias carries the Mithka X default art', () {
      final applicationTag = manifest.substring(
        0,
        manifest.indexOf('>', manifest.indexOf('<application')),
      );
      expect(
        applicationTag.contains(
          'android:icon="@mipmap/ic_launcher_mithkax_default"',
        ),
        isTrue,
        reason: 'the application icon (App info, task records) is the default',
      );
      final primordial = manifest.substring(
        manifest.indexOf('android:name=".MainActivityLetterMNeutral"'),
      );
      expect(
        primordial
            .substring(0, primordial.indexOf('</activity-alias>'))
            .contains('android:icon="@mipmap/ic_launcher_mithkax_default"'),
        isTrue,
        reason: 'the manifest-enabled alias must show the shipped default art',
      );
      expect(
        kt.contains('return "mithkax_default"'),
        isTrue,
        reason: 'a fresh install must report the new default to the picker',
      );
      expect(
        kt.contains('else "mithkax_default"'),
        isTrue,
        reason: 'an unknown setIcon target falls back to the shipped default',
      );
    });

    test('both fork marks are selectable through disabled aliases', () {
      for (final entry in {
        'mithkax_default': 'MainActivityMithkaXDefaultAlt',
        'mithkax_monochrome': 'MainActivityMithkaXMonochrome',
      }.entries) {
        expect(
          kt.contains('"${entry.key}" to "\$packageName.${entry.value}"'),
          isTrue,
          reason: '${entry.key} has no launcher alias',
        );
        final start = manifest.indexOf('android:name=".${entry.value}"');
        expect(
          start,
          isNot(-1),
          reason: '${entry.value} is not in the manifest',
        );
        expect(
          manifest
              .substring(start, start + 240)
              .contains('android:enabled="false"'),
          isTrue,
          reason: '${entry.value} must ship disabled like every alternative',
        );
      }
    });
  });

  group('picker section', () {
    testWidgets('the fork marks own the first section of the icon page', (
      tester,
    ) async {
      _mockBridge();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      final controller = AppIconController(prefs);
      addTearDown(theme.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: controller),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(extensions: [AppColors.light]),
            home: const AppIconSettingsView(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final heading = find.byKey(const ValueKey('app-icon-mithkax-heading'));
      final defaultTile = find.byKey(
        const ValueKey('app-icon-mithkax_default'),
      );
      final monoTile = find.byKey(
        const ValueKey('app-icon-mithkax_monochrome'),
      );
      final standardHeading = find.byKey(
        const ValueKey('app-icon-standard-heading'),
      );
      expect(heading, findsOneWidget);
      // The shipped en-US value, not the key and not the Chinese UI label.
      expect(tester.widget<Text>(heading).data, 'Mithka X icons');
      expect(defaultTile, findsOneWidget);
      expect(monoTile, findsOneWidget);
      expect(standardHeading, findsOneWidget);

      // A separate section ABOVE the motif grid, default first. Order comes
      // from the widget tree, so it holds regardless of viewport scrolling.
      final order = tester.allWidgets
          .map((widget) => widget.key)
          .whereType<ValueKey<String>>()
          .map((key) => key.value)
          .toList();
      expect(
        order.indexOf('app-icon-mithkax-heading'),
        lessThan(order.indexOf('app-icon-mithkax_default')),
      );
      expect(
        order.indexOf('app-icon-mithkax_default'),
        lessThan(order.indexOf('app-icon-mithkax_monochrome')),
      );
      expect(
        order.indexOf('app-icon-mithkax_monochrome'),
        lessThan(order.indexOf('app-icon-standard-heading')),
        reason: 'the Mithka X section sits above the standard icons',
      );
      expect(
        order.indexOf('app-icon-mithkax_monochrome'),
        lessThan(order.indexOf('app-icon-white')),
        reason: 'the fork marks never appear inside the motif grid',
      );

      // The shipped default is the one marked current.
      expect(
        find.byKey(const ValueKey('icon-selected-mithkax_default')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('icon-selected-mithkax_monochrome')),
        findsNothing,
      );

      // The fork marks never leak into the motif grid or the penguin grid.
      expect(
        find.byKey(const ValueKey('icon-label-white')),
        findsOneWidget,
        reason: 'the nine motif icons still render',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
