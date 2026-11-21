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
}
