//
//  message_action_dropdown_test.dart
//
//  The touch dropdown lays its options out at exteraless's popup scale: 44px
//  rows, 16pt labels, a 20pt glyph and a column that hugs its widest label
//  instead of a 36px pointer row squeezed into 220px. The desktop context menu
//  keeps its compact pointer rows.
//

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_action_menu.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  setUpAll(() => L10nFixtures.load().install());

  ChatMessage message() => ChatMessage(
    id: 1,
    isOutgoing: false,
    text: 'hello',
    date: 1700000000,
    chatId: 100,
    contentType: 'messageText',
  );

  /// Pumps the dropdown with [platform] as the target, resetting the debug
  /// override before the test's invariants are checked.
  Future<List<MessageAction>> pumpMenu(
    WidgetTester tester, {
    required TargetPlatform platform,
    required MessageActionMenuLayout layout,
  }) async {
    final picked = <MessageAction>[];
    debugDefaultTargetPlatformOverride = platform;
    SharedPreferences.setMockInitialValues({});
    final translation = TranslationController(
      await SharedPreferences.getInstance(),
    );
    addTearDown(translation.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<TranslationController>.value(
        value: translation,
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
          home: Scaffold(
            body: Center(
              child: MessageActionMenu(
                message: message(),
                isPinned: false,
                layout: layout,
                allowCopyMessageLink: true,
                onSelect: picked.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
    return picked;
  }

  double rowHeight(WidgetTester tester, String action) =>
      tester.getSize(find.byKey(ValueKey('message-action-$action'))).height;

  double surfaceWidth(WidgetTester tester) => tester
      .getSize(find.byKey(const ValueKey('message-action-menu-surface')))
      .width;

  TextStyle labelStyle(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!;

  testWidgets('touch dropdown gives every option a full-size row', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      platform: TargetPlatform.android,
      layout: MessageActionMenuLayout.vertical,
    );

    expect(
      rowHeight(tester, 'copy'),
      MessageActionMenu.mobileDropdownRowHeight,
    );
    expect(
      labelStyle(tester, 'Copy').fontSize,
      MessageActionMenu.mobileDropdownTextSize,
    );
  });

  testWidgets('touch dropdown hugs its widest label inside the bounds', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      platform: TargetPlatform.android,
      layout: MessageActionMenuLayout.vertical,
    );

    final width = surfaceWidth(tester);
    expect(
      width,
      greaterThanOrEqualTo(MessageActionMenu.mobileDropdownMinWidth),
    );
    expect(width, lessThanOrEqualTo(MessageActionMenu.mobileDropdownMaxWidth));
    expect(width, greaterThan(MessageActionMenu.desktopPreferredWidth));
  });

  testWidgets('desktop context menu keeps its compact pointer rows', (
    tester,
  ) async {
    await pumpMenu(
      tester,
      platform: TargetPlatform.linux,
      layout: MessageActionMenuLayout.vertical,
    );

    expect(rowHeight(tester, 'copy'), 36);
    expect(labelStyle(tester, 'Copy').fontSize, AppTextSize.callout);
    expect(surfaceWidth(tester), MessageActionMenu.desktopPreferredWidth);
  });

  testWidgets('tapping a dropdown row selects its action', (tester) async {
    final picked = await pumpMenu(
      tester,
      platform: TargetPlatform.android,
      layout: MessageActionMenuLayout.vertical,
    );

    await tester.tap(find.byKey(const ValueKey('message-action-forward')));
    await tester.pump();
    expect(picked, [MessageAction.forward]);
  });

  group('theme', () {
    Future<void> pumpIn(WidgetTester tester, ThemeData theme) async {
      SharedPreferences.setMockInitialValues({});
      final translation = TranslationController(
        await SharedPreferences.getInstance(),
      );
      addTearDown(translation.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<TranslationController>.value(
          value: translation,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            home: Scaffold(
              body: Center(
                child: MessageActionMenu(
                  message: message(),
                  isPinned: false,
                  layout: MessageActionMenuLayout.vertical,
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    BoxDecoration surfaceOf(WidgetTester tester) =>
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('message-action-menu-surface')),
                )
                .decoration!
            as BoxDecoration;

    testWidgets('day theme floats a light card with dark ink', (tester) async {
      await pumpIn(tester, ThemeData(extensions: [AppColors.light]));
      final decoration = surfaceOf(tester);
      expect(decoration.color, AppColors.light.card);
      expect(
        tester.widget<Text>(find.text('Copy')).style!.color,
        AppColors.light.textPrimary,
      );
    });

    testWidgets('night theme keeps the raised dark surface', (tester) async {
      await pumpIn(
        tester,
        ThemeData(brightness: Brightness.dark, extensions: [AppColors.dark]),
      );
      final decoration = surfaceOf(tester);
      expect(decoration.color, AppColors.dark.navBar);
      expect(
        tester.widget<Text>(find.text('Copy')).style!.color,
        AppColors.dark.textPrimary,
      );
    });
  });

  group('placement', () {
    const bottomSafe = 800.0;
    const topSafe = 0.0;
    const stripHeight = 48.0;

    MessageActionOverlayPlacement place({
      Rect? anchor = const Rect.fromLTWH(10, 700, 200, 60),
      double menuHeight = 544,
      bool startsAtAnchorTop = true,
    }) => MessageActionMenu.placeMobileOverlay(
      anchor: anchor,
      preferredMenuHeight: menuHeight,
      stripHeight: stripHeight,
      topSafe: topSafe,
      bottomSafe: bottomSafe,
      viewportHeight: 800,
      menuStartsAtAnchorTop: startsAtAnchorTop,
    );

    /// The strip is drawn above the bubble: 700 − 48 − 8.
    test('the strip stays glued above the message', () {
      expect(place().stripTop, 644);
    });

    test('a message at the bottom flips the menu above the strip', () {
      // Only 100pt below the strip: the full menu cannot fit there.
      final placement = place();
      expect(placement.menuHeight, 544);
      expect(placement.menuTop + placement.menuHeight, lessThanOrEqualTo(644));
      expect(placement.menuTop, greaterThanOrEqualTo(topSafe));
    });

    test('the menu never crosses the strip', () {
      for (final anchorTop in [120.0, 300.0, 500.0, 640.0, 700.0, 760.0]) {
        for (final menuHeight in [40.0, 200.0, 400.0, 544.0, 700.0]) {
          for (final startsAtTop in [true, false]) {
            final placement = place(
              anchor: Rect.fromLTWH(10, anchorTop, 200, 60),
              menuHeight: menuHeight,
              startsAtAnchorTop: startsAtTop,
            );
            final stripTop = placement.stripTop;
            final stripBottom = stripTop + stripHeight;
            final opensBelow = placement.menuTop >= stripBottom;
            final flippedAbove =
                placement.menuTop + placement.menuHeight <= stripTop;
            expect(
              opensBelow || flippedAbove,
              isTrue,
              reason:
                  'anchor $anchorTop, menu $menuHeight, top-anchored $startsAtTop, '
                  'strip $stripTop..$stripBottom, menu ${placement.menuTop}..'
                  '${placement.menuTop + placement.menuHeight}',
            );
            expect(placement.menuTop, greaterThanOrEqualTo(topSafe));
            expect(
              placement.menuTop + placement.menuHeight,
              lessThanOrEqualTo(bottomSafe),
            );
          }
        }
      }
    });

    test('a menu with room opens under the strip', () {
      final placement = place(
        anchor: const Rect.fromLTWH(10, 300, 200, 60),
        menuHeight: 300,
      );
      expect(placement.menuTop, 300);
      expect(placement.menuHeight, 300);
      expect(placement.menuTop + placement.menuHeight, lessThanOrEqualTo(700));
    });

    test('the grid style opens below the bubble', () {
      final placement = place(
        anchor: const Rect.fromLTWH(10, 200, 200, 60),
        menuHeight: 152,
        startsAtAnchorTop: false,
      );
      expect(placement.menuTop, 268);
      expect(placement.menuHeight, 152);
    });

    test('without a strip the menu opens at the bubble', () {
      final placement = MessageActionMenu.placeMobileOverlay(
        anchor: const Rect.fromLTWH(10, 300, 200, 60),
        preferredMenuHeight: 200,
        stripHeight: 0,
        topSafe: topSafe,
        bottomSafe: bottomSafe,
        viewportHeight: 800,
        menuStartsAtAnchorTop: true,
      );
      expect(placement.menuTop, 300);
      expect(placement.menuHeight, 200);
    });

    test('a menu taller than the screen takes the roomier side', () {
      final placement = place(menuHeight: 900);
      expect(placement.menuTop, topSafe);
      expect(placement.menuHeight, placement.stripTop - 8);
    });
  });
}
