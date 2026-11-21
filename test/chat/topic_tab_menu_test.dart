//
//  topic_tab_menu_test.dart
//
//  A long press on a topic tab opens the same narrow anchored menu as a folder
//  tab — pin / edit / delete, gated by the same rights the topic row menu
//  uses — instead of the wide bottom sheet. The General topic keeps its
//  permanently named identity: pin only, never edit or delete.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _forumChatId = -1009012;

Map<String, dynamic> _topic(
  int id,
  String name, {
  int lastMessageId = 0,
  bool isPinned = false,
  bool isGeneral = false,
}) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'forum_topic_id': id,
    'name': name,
    if (isGeneral) 'is_general': true,
    'icon': {'@type': 'forumTopicIcon', 'color': 0x6FB9F0},
  },
  'unread_count': 0,
  'is_pinned': isPinned,
  'last_message': {
    '@type': 'message',
    'id': lastMessageId,
    'chat_id': _forumChatId,
    'date': 1700000000 + lastMessageId,
    'is_outgoing': false,
    'sender_id': {'@type': 'messageSenderUser', 'user_id': 5},
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': 'last in $name'},
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final updates = StreamController<Map<String, dynamic>>.broadcast();
  final queries = <Map<String, dynamic>>[];

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          queries.add(request);
          switch (request['@type']) {
            case 'getChat':
              return {
                '@type': 'chat',
                'id': _forumChatId,
                'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 9012},
                'title': 'Forum Group',
                'unread_count': 0,
                'permissions': {'can_send_basic_messages': true},
              };
            case 'getSupergroup':
              // Creator: pin and edit ride can_manage_topics, delete rides
              // can_delete_messages — the row menu's own gates.
              return {
                '@type': 'supergroup',
                'id': 9012,
                'is_forum': true,
                'status': {'@type': 'chatMemberStatusCreator'},
              };
            case 'getSupergroupFullInfo':
              return {'@type': 'supergroupFullInfo', 'member_count': 8};
            case 'getForumTopics':
              return {
                '@type': 'forumTopics',
                'topics': [
                  _topic(
                    1,
                    'General',
                    lastMessageId: 10,
                    isPinned: true,
                    isGeneral: true,
                  ),
                  _topic(50, 'Announcements', lastMessageId: 500),
                ],
                'total_count': 2,
              };
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Test'};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  setUp(queries.clear);

  Future<void> openForum(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: const Scaffold(body: ChatListView()),
        ),
      ),
    );

    updates.add({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    updates.add({
      '@type': 'updateNewChat',
      'chat': {
        '@type': 'chat',
        'id': _forumChatId,
        'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 9012},
        'title': 'Forum Group',
        'is_forum': true,
        'positions': [
          {
            '@type': 'chatPosition',
            'list': {'@type': 'chatListMain'},
            'order': 100,
          },
        ],
      },
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forum Group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatView), findsOneWidget);
  }

  testWidgets('long press opens an anchored pin/edit/delete menu', (
    tester,
  ) async {
    await openForum(tester);

    await tester.longPress(find.byKey(const ValueKey('topic-tab-50')));
    await tester.pumpAndSettle();

    // The narrow popup, not the wide topic bottom sheet.
    final menu = find.byKey(const ValueKey('app-anchored-menu'));
    expect(menu, findsOneWidget);
    expect(find.byKey(const ValueKey('topic-selector-list')), findsNothing);
    expect(find.byKey(const ValueKey('app-anchored-menu-pin')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('app-anchored-menu-edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('app-anchored-menu-delete')),
      findsOneWidget,
    );
    // The tab's own name heads the menu (the strip's label is the other).
    expect(
      find.descendant(of: menu, matching: find.text('Announcements')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('app-anchored-menu-pin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-anchored-menu')), findsNothing);
    final pin = queries.lastWhere(
      (request) => request['@type'] == 'toggleForumTopicIsPinned',
    );
    expect(pin['chat_id'], _forumChatId);
    expect(pin['forum_topic_id'], 50);
    expect(pin['is_pinned'], true);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('the General topic only offers pin', (tester) async {
    await openForum(tester);

    await tester.longPress(find.byKey(const ValueKey('topic-tab-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-anchored-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-anchored-menu-pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-anchored-menu-edit')), findsNothing);
    expect(
      find.byKey(const ValueKey('app-anchored-menu-delete')),
      findsNothing,
    );

    await tester.tapAt(const Offset(10, 800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-anchored-menu')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
