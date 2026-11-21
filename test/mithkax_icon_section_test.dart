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
        AppIconVariant.mithkaxShadowLight,
        AppIconVariant.mithkaxShadowDark,
        AppIconVariant.mithkaxJade,
        AppIconVariant.mithkaxGoogleLight,
        AppIconVariant.mithkaxGoogleDark,
        AppIconVariant.mithkaxGlitch,
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

    test('the Android launcher carries every fork mark at every density', () {
      const densities = {
        'mdpi': 1,
        'hdpi': 1.5,
        'xhdpi': 2,
        'xxhdpi': 3,
        'xxxhdpi': 4,
      };
      // Derived from the catalogue, not a second list: a mark added to the
      // picker without its launcher resources fails right here.
      for (final variant in AppIconVariant.mithkaXSection) {
        final name = variant.key;
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

    test('every fork mark is a normal, free choice', () async {
      _mockBridge();
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppIconController(prefs);
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(
        controller.availableVariants,
        containsAll(AppIconVariant.mithkaXSection),
      );
      for (final variant in AppIconVariant.mithkaXSection) {
        expect(controller.isLocked(variant), isFalse);
        // Selecting the mark that is already applied short-circuits without
        // an explicit write (native state is already right); only a real
        // switch persists the choice. Aurora ships as the default, so the
        // first pass over the section hits exactly that path.
        final alreadyCurrent = controller.isCurrent(variant);
        expect(await controller.setVariant(variant), isTrue);
        if (!alreadyCurrent) {
          expect(prefs.getString('selected_app_icon'), variant.key);
        }
      }
    });

    test(
      'the retired monochrome key resolves to the shipped default',
      () async {
        _mockBridge();
        // An install that picked the retired mark still holds its key.
        SharedPreferences.setMockInitialValues({
          'selected_app_icon': 'mithkax_monochrome',
        });
        final prefs = await SharedPreferences.getInstance();
        final controller = AppIconController(prefs);
        addTearDown(controller.dispose);
        await controller.initialize();

        expect(
          AppIconVariant.recognizedFromKey('mithkax_monochrome'),
          AppIconVariant.mithkaxDefault,
        );
        expect(controller.currentKey, 'mithkax_default');
        expect(
          controller.retainedUnknownState,
          isNull,
          reason: 'a retired key is history, not an unknown identity',
        );
        expect(controller.firstChangePending, isFalse);
      },
    );
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

    test('every fork mark is selectable through a disabled alias', () {
      for (final entry in {
        'mithkax_default': 'MainActivityMithkaXDefaultAlt',
        'mithkax_shadow_light': 'MainActivityMithkaXShadowLight',
        'mithkax_shadow_dark': 'MainActivityMithkaXShadowDark',
        'mithkax_jade': 'MainActivityMithkaXJade',
        'mithkax_google_light': 'MainActivityMithkaXGoogleLight',
        'mithkax_google_dark': 'MainActivityMithkaXGoogleDark',
        'mithkax_glitch': 'MainActivityMithkaXGlitch',
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

    test('the native switch accepts every catalogued key', () {
      // The alias table is the single source of truth for "an icon that
      // exists". A second, hand-maintained key list once held the twelve
      // standard marks and the 48 penguins but not the fork's own two marks,
      // so tapping either answered "cannot change the app icon"
      // (invalid_icon) without ever reaching the launcher.
      expect(
        kt.contains('val freeIcons = setOf('),
        isFalse,
        reason: 'the setIcon gate must consult launcherAliases(), not a copy',
      );
      expect(
        kt.contains('if (!launcherAliases().containsKey(name))'),
        isTrue,
        reason: 'an unknown key is the only thing setIcon may reject',
      );
      for (final variant in AppIconVariant.values) {
        expect(
          kt.contains('"${variant.key}" to "\$packageName.'),
          isTrue,
          reason: '${variant.key} has no launcher alias to switch to',
        );
      }
    });

    test('the iOS bridge maps the same keys', () {
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      for (final variant in AppIconVariant.values) {
        expect(
          swift.contains('case "${variant.key}": return '),
          isTrue,
          reason: '${variant.key} has no alternate icon on iOS',
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
      final shadowTile = find.byKey(
        const ValueKey('app-icon-mithkax_shadow_light'),
      );
      final standardHeading = find.byKey(
        const ValueKey('app-icon-standard-heading'),
      );
      expect(heading, findsOneWidget);
      // The shipped en-US value, not the key and not the Chinese UI label.
      expect(tester.widget<Text>(heading).data, 'Mithka X icons');
      expect(defaultTile, findsOneWidget);
      expect(shadowTile, findsOneWidget);
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
        lessThan(order.indexOf('app-icon-mithkax_shadow_light')),
      );
      expect(
        order.indexOf('app-icon-mithkax_shadow_light'),
        lessThan(order.indexOf('app-icon-standard-heading')),
        reason: 'the Mithka X section sits above the standard icons',
      );
      expect(
        order.indexOf('app-icon-mithkax_glitch'),
        lessThan(order.indexOf('app-icon-white')),
        reason: 'the fork marks never appear inside the motif grid',
      );

      // The shipped default is the one marked current.
      expect(
        find.byKey(const ValueKey('icon-selected-mithkax_default')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('icon-selected-mithkax_shadow_light')),
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
