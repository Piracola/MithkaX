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
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/story_ui_components.dart';
import 'package:mithka/settings/about_view.dart';
import 'package:mithka/settings/appearance/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/typography_metrics.dart';
import 'support/l10n_fixtures.dart';

void _noop(bool _) {}

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

  testWidgets('story actions: typography geometry', (tester) async {
    // The story dialog actions are the one moments surface that mounts without
    // a live conversation, so it is what the probe can pin from this area. The
    // three weights are the whole hierarchy here: primary, secondary,
    // destructive.
    await pump(
      tester,
      Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StoryDialogAction(label: 'Share to story', onTap: () {}),
              StoryDialogAction(
                label: 'Save to gallery',
                primary: true,
                onTap: () {},
              ),
              StoryDialogAction(
                label: 'Delete story',
                destructive: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await expectTypographyBaseline(
      tester,
      'story_actions',
      collectTextRuns(tester),
    );
  });

  testWidgets('shared rows: typography geometry', (tester) async {
    // Every settings and list row in the app is built from these, so a literal
    // here is every screen's typography at once. Pinning them is what makes a
    // regression in the shared layer visible without rendering fifty screens.
    await pump(
      tester,
      const Scaffold(
        body: Column(
          children: [
            SettingsRow(title: 'Privacy and Security', value: 'Everyone'),
            SettingsRow(title: 'Data and Storage', showChevron: false),
            SettingsSwitchRow(
              title: 'Save to gallery',
              value: true,
              onChanged: _noop,
            ),
            SettingsNote(text: 'Changes apply to new messages only.'),
          ],
        ),
      ),
    );
    await expectTypographyBaseline(
      tester,
      'shared_rows',
      collectTextRuns(tester),
    );
  });
}
