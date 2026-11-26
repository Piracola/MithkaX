//
//  search_hit_avatar_shape_test.dart
//
//  Every search result leads with the peer's avatar. The result's own photo or
//  video preview used to take that slot as a rounded rectangle, so a Messages
//  hit looked like a square avatar and hid which chat it belonged to.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a peer hit draws a round avatar, never a square preview', (
    tester,
  ) async {
    await _pump(
      tester,
      const SearchHitLeadingImage(
        title: 'Ada',
        isPeer: true,
        size: 54,
        icon: HeroAppIcons.message,
        tint: Colors.blue,
      ),
    );
    final avatar = tester.widget<PhotoAvatar>(find.byType(PhotoAvatar));
    expect(avatar.square, isFalse);
    expect(avatar.size, 54);
    expect(find.byType(AppIcon), findsNothing);
  });

  testWidgets('a hit without an identity keeps its glyph in a circle', (
    tester,
  ) async {
    await _pump(
      tester,
      const SearchHitLeadingImage(
        title: 'Open chat',
        isPeer: false,
        size: 54,
        icon: HeroAppIcons.link,
        tint: Colors.blue,
      ),
    );
    expect(find.byType(PhotoAvatar), findsNothing);
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(SearchHitLeadingImage),
        matching: find.byType(Container),
      ),
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
  });

  testWidgets('a peer with a photo still draws the avatar', (tester) async {
    await _pump(
      tester,
      const SearchHitLeadingImage(
        title: 'Ada',
        isPeer: true,
        size: 40,
        icon: HeroAppIcons.message,
        tint: Colors.blue,
      ),
    );
    expect(
      tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).size,
      40,
      reason: 'the compact desktop row uses the same round avatar',
    );
  });
}
