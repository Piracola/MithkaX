//
//  about_view_test.dart
//
//  关于 draws the mark as ink, not as a square canvas: the mark asset is
//  the artwork with its transparent margins trimmed, so the app name sits one
//  gap token under the logo instead of under a band of empty pixels.
//

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/brand_mark.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/about_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  setUpAll(() => L10nFixtures.load().install());

  testWidgets('the about mark carries no transparent canvas', (tester) async {
    await tester.runAsync(() async {
      final data = await rootBundle.load('assets/brand_mark_ink.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final image = frame.image;
      addTearDown(image.dispose);
      final rgba = await image.toByteData();
      final bytes = rgba!.buffer.asUint8List();
      int alphaAt(int x, int y) => bytes[(y * image.width + x) * 4 + 3];

      // Every edge of the asset already holds ink: no transparent margin is
      // left for a layout to space against.
      var topInk = false, bottomInk = false;
      for (var x = 0; x < image.width && !(topInk && bottomInk); x++) {
        topInk = topInk || alphaAt(x, 0) > 0;
        bottomInk = bottomInk || alphaAt(x, image.height - 1) > 0;
      }
      var leftInk = false, rightInk = false;
      for (var y = 0; y < image.height && !(leftInk && rightInk); y++) {
        leftInk = leftInk || alphaAt(0, y) > 0;
        rightInk = rightInk || alphaAt(image.width - 1, y) > 0;
      }
      expect(topInk, isTrue, reason: 'transparent band above the mark');
      expect(bottomInk, isTrue, reason: 'transparent band below the mark');
      expect(leftInk, isTrue, reason: 'transparent band left of the mark');
      expect(rightInk, isTrue, reason: 'transparent band right of the mark');
    });
  });

  Future<void> pumpAbout(WidgetTester tester, Brightness brightness) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: brightness,
            extensions: [
              brightness == Brightness.dark ? AppColors.dark : AppColors.light,
            ],
          ),
          home: const AboutView(showBackButton: false),
        ),
      ),
    );
    // A ThemeData change animates through AnimatedTheme; settle so the mark
    // reads the appearance it was pumped with.
    await tester.pumpAndSettle();
  }

  testWidgets('the app name sits one gap under the mark', (tester) async {
    await pumpAbout(tester, Brightness.light);

    final mark = find.byType(Image).first;
    final name = find.text('Mithka X');
    final gap = tester.getTopLeft(name).dy - tester.getBottomLeft(mark).dy;
    expect(gap, AppSpacing.md);
    expect(tester.getSize(mark).height, 84);
  });

  testWidgets('the mark carries the aurora fill for its appearance', (
    tester,
  ) async {
    // Each appearance ships its own fill — azure ink on a light page, the
    // frost body on a dark one — so the widget must pick the matching asset
    // and must not tint over it.
    for (final (brightness, asset) in [
      (Brightness.light, brandMarkInkAsset),
      (Brightness.dark, brandMarkInkFrostAsset),
    ]) {
      await pumpAbout(tester, brightness);
      final mark = tester.widget<Image>(find.byType(Image).first);
      final provider = (mark.image as ResizeImage).imageProvider as AssetImage;
      expect(provider.assetName, asset, reason: '$brightness');
      expect(mark.color, isNull, reason: '$brightness');
    }
  });
}
