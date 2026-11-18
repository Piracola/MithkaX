//
//  topic_picker_view_test.dart
//
//  Opening a forum group from the chat list must land on the topic-selection
//  page (the exteraless middle step), not the "all chats" transcript; picking
//  a topic row opens that topic's transcript, and the All row opens the
//  whole chat.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/channels/topic_list_row.dart';
import 'package:mithka/channels/topic_picker_view.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _forumChatId = -1001234;

Map<String, dynamic> _topic(int id, String name, {int unread = 0}) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'forum_topic_id': id,
    'name': name,
    'icon': {'@type': 'forumTopicIcon', 'color': 0x6FB9F0},
  },
  'unread_count': unread,
  'is_pinned': false,
  'last_message': {
    '@type': 'message',
    'id': id * 10,
    'chat_id': _forumChatId,
    'date': 1700000000,
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

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getChat':
              return {
                '@type': 'chat',
                'id': _forumChatId,
                'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 1234},
                'title': 'Forum Group',
                'unread_count': 0,
                'permissions': {'can_send_basic_messages': true},
              };
            case 'getSupergroup':
              return {
                '@type': 'supergroup',
                'id': 1234,
                'is_forum': true,
                'status': {'@type': 'chatMemberStatusMember'},
              };
            case 'getSupergroupFullInfo':
              return {'@type': 'supergroupFullInfo', 'member_count': 8};
            case 'getForumTopics':
              return {
                '@type': 'forumTopics',
                'topics': [_topic(1, 'General'), _topic(50, 'Announcements')],
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

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final accounts = AccountStore(prefs);
    addTearDown(theme.dispose);
    addTearDown(accounts.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
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
  }

  ChatSummary forumSummary() => ChatSummary(
    id: _forumChatId,
    title: 'Forum Group',
    lastMessage: '',
    lastMessageId: 0,
    date: 0,
    unreadCount: 0,
    order: 0,
    isMuted: false,
    kind: ChatKind.group,
    isForum: true,
  );

  testWidgets('chat list opens a forum group on the topic picker', (
    tester,
  ) async {
    await pumpApp(tester);
    // Emit the forum chat into the list, the way the chat-list model feeds.
    updates.add({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
    updates.add({
      '@type': 'updateNewChat',
      'chat': {
        '@type': 'chat',
        'id': _forumChatId,
        'type': {'@type': 'chatTypeSupergroup', 'supergroup_id': 1234},
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
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(
      find.byType(TopicPickerView),
      findsOneWidget,
      reason: 'a forum group must land on the topic-selection page',
    );
    expect(find.byType(ChatView), findsNothing);
    // Tear down the pushed transcript so its periodic timers cannot leak.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a topic row opens that topic transcript; All opens the chat', (
    tester,
  ) async {
    // The picker needs the same provider tree the app supplies (NavHeader
    // reads ThemeController), so reuse the harness with a picker as the home.
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
          home: TopicPickerView(chat: forumSummary()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TopicListRowView), findsNWidgets(3));
    expect(find.text('Announcements'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.text('Announcements'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TopicPickerView), findsNothing);
    final chat = find.byType(ChatView);
    expect(chat, findsOneWidget);

    // Tear down the transcript and verify the All row also opens a chat.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    // Re-pump the picker for the All row test.
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
          home: TopicPickerView(chat: forumSummary()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatView), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
