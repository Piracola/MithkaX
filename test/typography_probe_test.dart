//
//  typography_probe_test.dart
//
//  Renders the surfaces a typography batch touches and pins the geometry each
//  text run lays out at. A batch that only changes a literal to a token leaves
//  these numbers identical; a batch that changes the hierarchy moves them, and
//  the baseline diff is what the review reads.
//
//  Scenes are added one area per batch, so the probe grows with the migration
//  instead of landing as one unreviewable commit.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/about_view.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/typography_metrics.dart';
import 'support/l10n_fixtures.dart';

void main() {
  setUpAll(() => L10nFixtures.load().install());

  /// The app's own harness: localization catalogue, both themes, a controller.
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Size size = const Size(900, 1600),
    Brightness brightness = Brightness.light,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final appIcons = AppIconController(prefs);
    addTearDown(theme.dispose);
    addTearDown(appIcons.dispose);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AppIconController>.value(value: appIcons),
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
          theme: ThemeData(
            brightness: brightness,
            extensions: [
              brightness == Brightness.dark ? AppColors.dark : AppColors.light,
            ],
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('appearance: typography geometry', (tester) async {
    await pump(tester, const AppearanceView());
    await expectTypographyBaseline(
      tester,
      'appearance',
      collectTextRuns(tester),
    );
  });

  testWidgets('about: typography geometry', (tester) async {
    await pump(tester, const AboutView(showBackButton: false));
    await expectTypographyBaseline(tester, 'about', collectTextRuns(tester));
  });
}
