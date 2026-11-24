//
//  chat_header_menu_test.dart
//
//  The chat header's `⋮` menu — exteraless's chat_menu_options column:
//
//  * every chat type carries it, so search has one predictable home;
//  * search leads the column and no longer holds a header glyph of its own;
//  * the column is the HEADER family (48px rows, 16sp labels, right edge under
//    the button) and stays visually distinct from the chat-info control;
//  * a topic chat's header action starts a topic (the title already opens the
//    topic list), and it disappears without the right to create one —
//    including a topics bot, whose permission is its own flag, never a
//    supergroup right.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/pinned_messages_view.dart';
import 'package:mithka/components/app_anchored_menu.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _privateChatId = 4242;
const _peerUserId = 7001;
const _groupChatId = -1009101;
const _groupSupergroupId = 9101;
const _channelChatId = -1009202;
const _channelSupergroupId = 9202;
const _forumChatId = -1009303;
const _forumSupergroupId = 9303;
const _botChatId = 770011;
const _botUserId = 7701;
const _unjoinedChannelId = -1009404;
const _unjoinedChannelSupergroupId = 9404;

enum _Kind {
  privateChat,
  group,
  channel,
  forumCreator,
  forumMember,
  botTopics,
  botWithoutTopicRights,
  unjoinedChannel,
}

_Kind _kind = _Kind.privateChat;
bool _hasPinnedMessage = false;
final _queries = <Map<String, dynamic>>[];

int get _chatId => switch (_kind) {
  _Kind.privateChat => _privateChatId,
  _Kind.group => _groupChatId,
  _Kind.channel => _channelChatId,
  _Kind.forumCreator || _Kind.forumMember => _forumChatId,
  _Kind.botTopics || _Kind.botWithoutTopicRights => _botChatId,
  _Kind.unjoinedChannel => _unjoinedChannelId,
};

Map<String, dynamic> _message(int id, {String text = 'hello'}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1785862260 + id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': _peerUserId},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text, 'entities': <Object>[]},
  },
};

Map<String, dynamic> _chat() {
  final (type, title) = switch (_kind) {
    _Kind.privateChat => (
      {'@type': 'chatTypePrivate', 'user_id': _peerUserId},
      'Friend',
    ),
    _Kind.group => (
      {
        '@type': 'chatTypeSupergroup',
        'supergroup_id': _groupSupergroupId,
        'is_channel': false,
      },
      'Team',
    ),
    _Kind.channel => (
      {
        '@type': 'chatTypeSupergroup',
        'supergroup_id': _channelSupergroupId,
        'is_channel': true,
      },
      'News',
    ),
    _Kind.forumCreator || _Kind.forumMember => (
      {
        '@type': 'chatTypeSupergroup',
        'supergroup_id': _forumSupergroupId,
        'is_channel': false,
      },
      'Forum',
    ),
    _Kind.botTopics || _Kind.botWithoutTopicRights => (
      {'@type': 'chatTypePrivate', 'user_id': _botUserId},
      'Topic Bot',
    ),
    _Kind.unjoinedChannel => (
      {
        '@type': 'chatTypeSupergroup',
        'supergroup_id': _unjoinedChannelSupergroupId,
        'is_channel': true,
      },
      'Unjoined News',
    ),
  };
  return {
    '@type': 'chat',
    'id': _chatId,
    'type': type,
    'title': title,
    'unread_count': 0,
    'last_read_inbox_message_id': 1,
    'permissions': {
      '@type': 'chatPermissions',
      'can_send_basic_messages': true,
    },
    if (_kind == _Kind.forumCreator || _kind == _Kind.forumMember)
      'is_forum': true,
  };
}

Map<String, dynamic> _topic(int id, String name, {bool isGeneral = false}) => {
  '@type': 'forumTopic',
  'info': {
    '@type': 'forumTopicInfo',
    'forum_topic_id': id,
    'name': name,
    if (isGeneral) 'is_general': true,
    'icon': {'@type': 'forumTopicIcon', 'color': 0x6FB9F0},
  },
  'unread_count': 0,
  'is_pinned': false,
  'last_message': {
    '@type': 'message',
    'id': 100 + id,
    'chat_id': _chatId,
    'date': 1785862260 + id,
    'is_outgoing': false,
    'sender_id': {'@type': 'messageSenderUser', 'user_id': 5},
    'content': {
      '@type': 'messageText',
      'text': {'@type': 'formattedText', 'text': 'last in $name'},
    },
  },
};

Map<String, dynamic> _supergroup() {
  final status = switch (_kind) {
    _Kind.forumCreator => {'@type': 'chatMemberStatusCreator'},
    _Kind.unjoinedChannel => {'@type': 'chatMemberStatusLeft'},
    _ => {'@type': 'chatMemberStatusMember'},
  };
  return {
    '@type': 'supergroup',
    'id': switch (_kind) {
      _Kind.channel => _channelSupergroupId,
      _Kind.unjoinedChannel => _unjoinedChannelSupergroupId,
      _Kind.forumCreator || _Kind.forumMember => _forumSupergroupId,
      _ => _groupSupergroupId,
    },
    'is_forum': _kind == _Kind.forumCreator || _kind == _Kind.forumMember,
    'status': status,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<Map<String, dynamic>> updates;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          _queries.add(request);
          switch (request['@type']) {
            case 'getChat':
              return _chat();
            case 'getUser':
              if (request['user_id'] == _botUserId) {
                return {
                  '@type': 'user',
                  'id': _botUserId,
                  'first_name': 'Topic Bot',
                  'type': {
                    '@type': 'userTypeBot',
                    'has_topics': true,
                    'allows_users_to_create_topics': _kind == _Kind.botTopics,
                  },
                };
              }
              return {
                '@type': 'user',
                'id': request['user_id'] ?? _peerUserId,
                'first_name': 'Ann',
                'type': {'@type': 'userTypeRegular'},
              };
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Me'};
            case 'getSupergroup':
              return _supergroup();
            case 'getSupergroupFullInfo':
              return {'@type': 'supergroupFullInfo', 'member_count': 8};
            case 'getBasicGroup':
              return {'@type': 'basicGroup', 'id': 1, 'member_count': 3};
            case 'getChatHistory':
              return {
                '@type': 'messages',
                'total_count': _kind == _Kind.unjoinedChannel ? 0 : 1,
                'messages': _kind == _Kind.unjoinedChannel
                    ? const <Object>[]
                    : [_message(1)],
              };
            case 'searchChatMessages':
              final filter = request['filter'];
              final pinned =
                  filter is Map &&
                  filter['@type'] == 'searchMessagesFilterPinned';
              return {
                '@type': 'foundChatMessages',
                'total_count': pinned && _hasPinnedMessage ? 1 : 0,
                'messages': pinned && _hasPinnedMessage
                    ? [_message(900, text: 'pinned note')]
                    : const <Object>[],
                'next_from_message_id': 0,
              };
            case 'getForumTopics':
              if (_kind == _Kind.botTopics ||
                  _kind == _Kind.botWithoutTopicRights) {
                return {
                  '@type': 'forumTopics',
                  'topics': [_topic(900, 'Releases')],
                  'total_count': 1,
                };
              }
              return {
                '@type': 'forumTopics',
                'topics': [
                  _topic(1, 'General', isGeneral: true),
                  _topic(50, 'Announcements'),
                ],
                'total_count': 2,
              };
            case 'getOption':
              return {'@type': 'optionValueInteger', 'value': '1024'};
            case 'getCountries':
              return {'@type': 'countries', 'countries': const []};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
    updates.add({
      '@type': 'updateConnectionState',
      'state': {'@type': 'connectionStateReady'},
    });
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  setUp(() {
    _kind = _Kind.privateChat;
    _hasPinnedMessage = false;
    _queries.clear();
  });

  Future<void> openChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    final locale = AppLocaleController(prefs);
    final accounts = AccountStore(prefs);
    final auth = AuthManager();
    final translation = TranslationController(prefs);
    final drawer = dc.DrawerController();
    addTearDown(theme.dispose);
    addTearDown(locale.dispose);
    addTearDown(accounts.dispose);
    addTearDown(auth.dispose);
    addTearDown(translation.dispose);
    addTearDown(drawer.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<AppLocaleController>.value(value: locale),
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<AuthManager>.value(value: auth),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
          ChangeNotifierProvider<dc.DrawerController>.value(value: drawer),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: ChatView(chatId: _chatId, title: 'Chat'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('chatHeaderMenu')));
    await tester.pumpAndSettle();
  }

  Future<void> closeChat(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  AppIconData headerIcon(WidgetTester tester, String key) => tester
      .widget<AppIcon>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(AppIcon),
        ),
      )
      .icon;

  testWidgets('every chat type carries the overflow menu, none a search icon', (
    tester,
  ) async {
    for (final kind in _Kind.values) {
      if (kind == _Kind.unjoinedChannel) continue; // its own case below
      _kind = kind;
      await openChat(tester);

      expect(
        find.byKey(const ValueKey('chatHeaderMenu')),
        findsOneWidget,
        reason: '$kind must offer the chat menu',
      );
      expect(
        find.byKey(const ValueKey('chatHeaderSearch')),
        findsNothing,
        reason: '$kind must not keep a standalone search glyph',
      );
      // The details control stays its own button; the menu is the only new
      // header item.
      expect(find.byKey(const ValueKey('chatHeaderInfo')), findsOneWidget);

      await closeChat(tester);
    }
  });

  testWidgets('search leads the menu and opens the in-chat search', (
    tester,
  ) async {
    await openChat(tester);
    await openMenu(tester);

    expect(find.text('Search in chat'), findsOneWidget);
    final search = find.byKey(const ValueKey('app-anchored-menu-search'));
    expect(search, findsOneWidget);
    final mute = find.byKey(const ValueKey('app-anchored-menu-mute'));
    expect(mute, findsOneWidget);
    expect(
      tester.getTopLeft(search).dy,
      lessThan(tester.getTopLeft(mute).dy),
      reason: 'search is the first option',
    );

    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chatSearchField')), findsOneWidget);

    await closeChat(tester);
  });

  testWidgets('the chat menu draws the header family, not a tab column', (
    tester,
  ) async {
    await openChat(tester);
    final button = tester.getRect(find.byKey(const ValueKey('chatHeaderMenu')));
    await openMenu(tester);

    final menu = tester.getRect(
      find.byKey(const ValueKey('app-anchored-menu')),
    );
    expect(
      menu.right,
      closeTo(button.right, 1),
      reason: 'the column hangs off its own button, right edge on right edge',
    );
    expect(menu.top, closeTo(button.bottom + AppSpacing.xs, 1));
    expect(menu.width, greaterThanOrEqualTo(196));

    final row = find.byKey(const ValueKey('app-anchored-menu-search'));
    expect(tester.getSize(row).height, 48);
    final label = tester.widget<Text>(
      find.descendant(of: row, matching: find.byType(Text)),
    );
    expect(label.style?.fontSize, AppTextSize.bodyLarge);

    // The compact tab column keeps its own 36px row; the two families must
    // not collapse into one.
    expect(tester.getSize(row).height, isNot(appAnchoredMenuRowHeight));

    await closeChat(tester);
  });

  testWidgets('the overflow glyph is distinct from the chat-info control', (
    tester,
  ) async {
    await openChat(tester);

    expect(headerIcon(tester, 'chatHeaderInfo'), HeroAppIcons.bars);
    expect(headerIcon(tester, 'chatHeaderMenu'), HeroAppIcons.ellipsisVertical);
    expect(
      headerIcon(tester, 'chatHeaderMenu'),
      isNot(headerIcon(tester, 'chatHeaderInfo')),
    );

    await closeChat(tester);
  });

  testWidgets('a forum creator starts a topic from the header', (tester) async {
    _kind = _Kind.forumCreator;
    await openChat(tester);

    // The title opens the list; the header's own action starts a topic.
    expect(find.byKey(const ValueKey('chatHeaderTopics')), findsNothing);
    final newTopic = find.byKey(const ValueKey('chatHeaderNewTopic'));
    expect(newTopic, findsOneWidget);
    expect(headerIcon(tester, 'chatHeaderNewTopic'), HeroAppIcons.plus);

    await tester.tap(newTopic);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-draft-name')),
      'Release notes',
    );
    await tester.tap(find.byKey(const ValueKey('topic-draft-save')));
    await tester.pumpAndSettle();

    final create = _queries.lastWhere(
      (request) => request['@type'] == 'createForumTopic',
    );
    expect(create['chat_id'], _forumChatId);
    expect(create['name'], 'Release notes');

    await closeChat(tester);
  });

  testWidgets('a topics bot gets the new-topic button from its own flag', (
    tester,
  ) async {
    _kind = _Kind.botTopics;
    await openChat(tester);

    expect(find.byKey(const ValueKey('chatHeaderNewTopic')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chatHeaderNewTopic')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('topic-draft-name')),
      'New subject',
    );
    await tester.tap(find.byKey(const ValueKey('topic-draft-save')));
    await tester.pumpAndSettle();

    final create = _queries.lastWhere(
      (request) => request['@type'] == 'createForumTopic',
    );
    expect(create['chat_id'], _botChatId);

    await closeChat(tester);
  });

  testWidgets('no create right, no new-topic button', (tester) async {
    for (final kind in [_Kind.forumMember, _Kind.botWithoutTopicRights]) {
      _kind = kind;
      await openChat(tester);

      expect(
        find.byKey(const ValueKey('chatHeaderNewTopic')),
        findsNothing,
        reason: '$kind has no right to start a topic',
      );
      // The topic list is still reachable — through the title.
      expect(find.byKey(const ValueKey('chatHeaderTitle')), findsOneWidget);

      await closeChat(tester);
    }
  });

  testWidgets('the pinned row exists only when a message is pinned', (
    tester,
  ) async {
    await openChat(tester);
    await openMenu(tester);
    expect(
      find.byKey(const ValueKey('app-anchored-menu-pinned-messages')),
      findsNothing,
    );
    await tester.tapAt(const Offset(10, 800));
    await tester.pumpAndSettle();
    await closeChat(tester);

    _hasPinnedMessage = true;
    await openChat(tester);
    await openMenu(tester);
    final pinned = find.byKey(
      const ValueKey('app-anchored-menu-pinned-messages'),
    );
    expect(pinned, findsOneWidget);
    expect(find.text('Pinned Messages'), findsOneWidget);

    await tester.tap(pinned);
    await tester.pumpAndSettle();
    expect(find.byType(PinnedMessagesView), findsOneWidget);

    await closeChat(tester);
  });

  testWidgets('mute toggles the chat notification settings', (tester) async {
    await openChat(tester);
    await openMenu(tester);
    expect(find.text('Mute'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-anchored-menu-mute')));
    await tester.pumpAndSettle();
    final mute = _queries.lastWhere(
      (request) => request['@type'] == 'setChatNotificationSettings',
    );
    final settings = mute['notification_settings'] as Map<String, dynamic>;
    expect(settings['mute_for'], 2147483647);

    // The row names what the next tap does, exteraless's state-paired label.
    await openMenu(tester);
    expect(find.text('Unmute'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('app-anchored-menu-mute')));
    await tester.pumpAndSettle();
    final unmute = _queries.lastWhere(
      (request) => request['@type'] == 'setChatNotificationSettings',
    );
    expect(
      (unmute['notification_settings'] as Map<String, dynamic>)['mute_for'],
      0,
    );

    await closeChat(tester);
  });
  testWidgets('a join screen with nothing to act on has no overflow button', (
    tester,
  ) async {
    _kind = _Kind.unjoinedChannel;
    await openChat(tester);

    expect(find.byKey(const ValueKey('chatHeaderMenu')), findsNothing);
    expect(find.byKey(const ValueKey('chatHeaderSearch')), findsNothing);

    await closeChat(tester);
  });
}
