//
//  pinned_messages_view_test.dart
//
//  The long-press pinned browser is the reference client's MODE_PINNED
//  transcript: bubbles, a "N Pinned Messages" title, a bottom bar that unpins
//  everything (or hides the bar), and a tap that closes the page with the
//  message to jump to.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/chat/pinned_messages_view.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/l10n_fixtures.dart';

const _chatId = -1005001;
const _senderId = 7001;

Map<String, dynamic> _message(int id, String text) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1785862260 + id,
  'is_outgoing': false,
  'sender_id': {'@type': 'messageSenderUser', 'user_id': _senderId},
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text, 'entities': <Object>[]},
  },
};

Map<String, dynamic> _chat({bool canPin = true}) => {
  '@type': 'chat',
  'id': _chatId,
  'type': {
    '@type': 'chatTypeSupergroup',
    'supergroup_id': 5001,
    'is_channel': false,
  },
  'title': 'Team',
  'permissions': {'@type': 'chatPermissions', 'can_pin_messages': canPin},
};

void main() {
  late StreamController<Map<String, dynamic>> updates;
  final queries = <Map<String, dynamic>>[];
  var canPinValue = true;
  var configured = false;

  setUpAll(() {
    L10nFixtures.load().install();
    updates = StreamController<Map<String, dynamic>>.broadcast();
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  void installTransport({bool canPin = true}) {
    queries.clear();
    canPinValue = canPin;
    if (configured) return;
    configured = true;
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          queries.add(request);
          switch (request['@type']) {
            case 'searchChatMessages':
              return {
                '@type': 'messages',
                'total_count': 2,
                'messages': [
                  _message(12, 'second pinned'),
                  _message(11, 'first pinned'),
                ],
              };
            case 'getChat':
              return _chat(canPin: canPinValue);
            case 'getMe':
              return {'@type': 'user', 'id': 1, 'first_name': 'Me'};
            case 'getUser':
              return {
                '@type': 'user',
                'id': _senderId,
                'first_name': 'Ann',
                'type': {'@type': 'userTypeRegular'},
              };
            default:
              return {'@type': 'ok'};
          }
        },
        send: (request) async {},
        updates: updates.stream,
      ),
    );
  }

  Future<Object? Function()> pumpPage(
    WidgetTester tester, {
    bool canPin = true,
  }) async {
    installTransport(canPin: canPin);
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    Object? result;
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () async {
                    result = await Navigator.of(context).push<Object>(
                      MaterialPageRoute<Object>(
                        builder: (_) => const PinnedMessagesView(
                          chatId: _chatId,
                          title: 'Team',
                        ),
                      ),
                    );
                  },
                  child: const Text('open', key: ValueKey('openPinned')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('openPinned')));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('the pinned list is a transcript with a count and an unpin bar', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('2 Pinned Messages'), findsOneWidget);
    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(find.text('Unpin all Messages'), findsOneWidget);
    expect(find.byType(TimeSeparator), findsOneWidget);
  });

  testWidgets('a tap closes the list with the message to jump to', (
    tester,
  ) async {
    final result = await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('pinnedMessage-12')));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedMessagesView), findsNothing);
    expect(result(), 12, reason: 'the chat scrolls to the tapped message');
  });

  testWidgets('an account that may not pin gets the hide action', (
    tester,
  ) async {
    final result = await pumpPage(tester, canPin: false);
    expect(find.text('Hide pinned Messages'), findsOneWidget);
    expect(find.text('Unpin all Messages'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pinnedMessagesBottomAction')));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedMessagesView), findsNothing);
    expect(result(), PinnedMessagesExit.hide);
  });

  testWidgets('unpinning calls TDLib and closes the list', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('pinnedMessagesBottomAction')));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedMessagesView), findsNothing);
    expect(
      queries.any((q) => q['@type'] == 'unpinAllChatMessages'),
      isTrue,
      reason: 'the bottom bar must unpin every message, not just hide the bar',
    );
  });
}
