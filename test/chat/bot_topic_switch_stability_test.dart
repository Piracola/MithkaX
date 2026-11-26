//
//  bot_topic_switch_stability_test.dart
//
//  Switching topics rebuilds the conversation route (ChatView reads its topic
//  once), so the fresh transcript must paint its topic chrome before the async
//  getChat/getUser round trips land. Without the cached topic-surface facts the
//  first frame fell back to a bot-less chat: the side dock flipped to the top
//  strip, the move control vanished, the title grew a topic chevron and the
//  new-topic button disappeared — a visible flash on every tab tap.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/channels/topic_navigation.dart';
import 'package:mithka/channels/topic_tabs_placement.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 700;
const _botUserId = 42;
const _topicA = 61474;
const _topicB = 61753;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => _response(request),
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
  });

  Future<void> openBotChat(
    WidgetTester tester,
    TopicTabsPlacement placement,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    TopicTabsPlacementStore.shared.resetForTesting();
    SharedPreferences.setMockInitialValues({
      'showChannelsTab': false,
      'showMomentsTab': false,
      'communitiesEnabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await TopicTabsPlacementStore.shared.save(0, _chatId, placement);
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
          ChangeNotifierProvider<AppLocaleController>.value(
            value: AppLocaleController(prefs),
          ),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const _FirstPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 2));
  }

  Finder titleChevron() => find.descendant(
    of: find.byKey(const ValueKey('chatHeaderTitle')),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is AppIcon && identical(widget.icon, HeroAppIcons.chevronDown),
    ),
  );

  testWidgets('a bot topic switch keeps the side dock on the first frame', (
    tester,
  ) async {
    await openBotChat(tester, TopicTabsPlacement.side);

    final sideBar = find.byType(TopicTabsSideBar);
    expect(sideBar, findsOneWidget);
    final before = tester.getRect(sideBar);
    expect(titleChevron(), findsNothing);

    await tester.tap(find.byKey(const ValueKey('topic-tab-$_topicB')));
    // The first frame of the replacement transcript.
    await tester.pump();

    expect(
      find.byType(TopicTabStrip),
      findsNothing,
      reason: 'the side dock must not flash back to the top strip',
    );
    expect(sideBar, findsOneWidget);
    expect(
      tester.getRect(sideBar),
      before,
      reason: 'the topic chrome must not move during the swap',
    );
    expect(
      find.byKey(const ValueKey('topic-tabs-placement-toggle')),
      findsOneWidget,
      reason: 'the move control belongs to the new bot transcript too',
    );
    expect(
      titleChevron(),
      findsNothing,
      reason: 'a bot topic chat never grows the topic chevron',
    );
    expect(
      find.byKey(const ValueKey('chatHeaderNewTopic')),
      findsOneWidget,
      reason: 'the new-topic button must survive the swap',
    );

    await tester.pumpAndSettle();
    expect(find.byType(TopicTabStrip), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });

  testWidgets('a bot topic switch keeps the move control on the first frame', (
    tester,
  ) async {
    await openBotChat(tester, TopicTabsPlacement.top);

    expect(
      find.byKey(const ValueKey('topic-tabs-placement-toggle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('topic-tab-$_topicB')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('topic-tabs-placement-toggle')),
      findsOneWidget,
      reason: 'the first frame must not draw a toggle-less strip',
    );
    expect(titleChevron(), findsNothing);

    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });
}

class _FirstPage extends StatelessWidget {
  const _FirstPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const ChatView(chatId: _chatId, title: 'Topic Bot'),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Map<String, dynamic> _response(Map<String, dynamic> request) =>
    switch (request['@type']) {
      'getChat' => {
        '@type': 'chat',
        'id': _chatId,
        'title': 'Topic Bot',
        'type': {'@type': 'chatTypePrivate', 'user_id': _botUserId},
        'permissions': {
          '@type': 'chatPermissions',
          'can_send_basic_messages': true,
        },
      },
      'getUser' => {
        '@type': 'user',
        'id': _botUserId,
        'first_name': 'Topic',
        'last_name': 'Bot',
        'type': {
          '@type': 'userTypeBot',
          'has_topics': true,
          'allows_users_to_create_topics': true,
        },
      },
      'getSupergroup' => {
        '@type': 'error',
        'message': 'chat not found',
        'code': 400,
      },
      'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Me'},
      'getConnectionState' => {'@type': 'connectionStateReady'},
      'getForumTopics' => {
        '@type': 'forumTopics',
        'topics': [
          _topic(_topicA, 'Topic A', _message(10, 'A first')),
          _topic(_topicB, 'Topic B', _message(12, 'B first')),
        ],
      },
      'getChatHistory' => {'@type': 'messages', 'messages': _history},
      'getMessage' => _message(request['message_id'] as int, 'Fetched'),
      _ => {'@type': 'ok'},
    };

Map<String, dynamic> _topic(
  int id,
  String name,
  Map<String, dynamic> lastMessage,
) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'chat_id': _chatId,
    'forum_topic_id': id,
    'name': name,
  },
  'last_message': lastMessage,
};

final List<Map<String, dynamic>> _history = [
  _message(10, 'A first', topicId: _topicA),
  _message(11, 'A second', topicId: _topicA, outgoing: true),
  _message(12, 'B first', topicId: _topicB),
  _message(13, 'B second', topicId: _topicB, outgoing: true),
];

Map<String, dynamic> _message(
  int id,
  String text, {
  int? topicId,
  bool outgoing = false,
}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1700000000 + id,
  'is_outgoing': outgoing,
  'sender_id': {
    '@type': 'messageSenderUser',
    'user_id': outgoing ? 1 : _botUserId,
  },
  if (topicId != null)
    'topic_id': {'@type': 'messageTopicForum', 'forum_topic_id': topicId},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
};
