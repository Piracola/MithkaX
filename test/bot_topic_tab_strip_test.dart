//
//  bot_topic_tab_strip_test.dart
//
//  The bot-chat topic strip must borrow the chat list's folder-tab language:
//  an "All" tab first, per-topic tabs with the folder-style unread badge
//  pill, and the 4pt selection indicator under the chosen tab only.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_navigation.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

const _botChatAllTabKey = ValueKey('topic-tab-all');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpStrip(
    WidgetTester tester, {
    required List<TopicNavigationItem> topics,
    int? selectedTopicId,
    bool showUnreadBadges = true,
    ValueChanged<int?>? onSelected,
  }) async {
    final selections = <int?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TopicTabStrip(
            topics: topics,
            selectedTopicId: selectedTopicId,
            showUnreadBadges: showUnreadBadges,
            onSelected: onSelected ?? selections.add,
          ),
        ),
      ),
    );
    await tester.pump();
    return;
  }

  final topics = [
    const TopicNavigationItem(id: 10, name: 'Support', unreadCount: 3),
    const TopicNavigationItem(
      id: 20,
      name: 'FAQ',
      unreadCount: 150,
      isMuted: true,
    ),
  ];

  testWidgets('renders All tab first, then topic tabs with badges', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpStrip(tester, topics: topics);

    expect(find.byKey(_botChatAllTabKey), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);
    // Folder-style badge pills after each topic label.
    expect(find.byType(FolderUnreadBadge), findsNWidgets(2));
    expect(find.byKey(const ValueKey('topic-tab-unread-10')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-tab-unread-10')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    // The overflow cap matches the folder badge default (99+).
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-tab-unread-20')),
        matching: find.text('99+'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('honours the folder badge visibility setting', (tester) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpStrip(tester, topics: topics, showUnreadBadges: false);
    expect(find.byType(FolderUnreadBadge), findsNothing);
  });

  testWidgets('selection follows the open transcript and taps switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final selections = <int?>[];
    await pumpStrip(
      tester,
      topics: topics,
      selectedTopicId: 20,
      onSelected: selections.add,
    );

    // The selected tab's 4pt indicator paints solid brand; the unselected
    // tabs keep the fully transparent variant, so exactly one is lit.
    final lit = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).color == AppTheme.brand &&
          (widget.constraints is BoxConstraints) &&
          (widget.constraints as BoxConstraints).maxHeight == 4,
    );
    expect(lit, findsOneWidget);

    await tester.tap(find.text('Support'));
    await tester.pump();
    expect(selections, equals([10]));

    await tester.tap(find.text('All'));
    await tester.pump();
    expect(selections, equals([10, null]));
  });
}
