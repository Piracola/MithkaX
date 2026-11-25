//
//  message_arrival_test.dart
//
//  A message that lands in an open transcript plays a short entrance; a row
//  that was already on screen (initial page, history page-in, scroll rebind)
//  must never replay it. These pin both halves plus the resting fast path.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/messages/message_arrival.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 880;
const _peerUserId = 881;

Map<String, dynamic> _message(int id, String text, {bool outgoing = false}) => {
  '@type': 'message',
  'id': id,
  'chat_id': _chatId,
  'date': 1700000000 + id,
  'is_outgoing': outgoing,
  'sender_id': {
    '@type': 'messageSenderUser',
    'user_id': outgoing ? 1 : _peerUserId,
  },
  'content': {
    '@type': 'messageText',
    'text': {'@type': 'formattedText', 'text': text},
  },
};

final _history = <Map<String, dynamic>>[
  _message(1, 'History hello'),
  _message(2, 'History again'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageArrival widget', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool animate,
      bool outgoing = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageArrival(
              animate: animate,
              outgoing: outgoing,
              child: const SizedBox(width: 120, height: 40, child: Text('hi')),
            ),
          ),
        ),
      );
    }

    Opacity? opacityOf(WidgetTester tester) {
      final finder = find.descendant(
        of: find.byType(MessageArrival),
        matching: find.byType(Opacity),
      );
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Opacity>(finder.first);
    }

    testWidgets('a live arrival fades and rises into place', (tester) async {
      await pump(tester, animate: true);
      expect(opacityOf(tester)?.opacity, 0);
      final rises = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(MessageArrival),
              matching: find.byType(Transform),
            ),
          )
          .map((transform) => transform.transform.getTranslation().y);
      expect(rises.any((dy) => dy > 0), isTrue);

      await tester.pump(const Duration(milliseconds: 120));
      final mid = opacityOf(tester)?.opacity ?? 1;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(1));

      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityOf(tester), isNull);
      expect(
        tester.getRect(find.byType(MessageArrival)),
        tester.getRect(find.text('hi')),
      );
    });

    testWidgets('an existing row paints at rest with no wrapper', (
      tester,
    ) async {
      await pump(tester, animate: false);
      expect(opacityOf(tester), isNull);
    });
  });

  group('new message in an open transcript', () {
    late StreamController<Map<String, dynamic>> updates;

    setUpAll(() {
      updates = StreamController<Map<String, dynamic>>.broadcast();
      TdClient.shared.configureProxy(
        TdClientProxyTransport(
          accountSlot: 0,
          query: (request) async => switch (request['@type']) {
            'getChat' => {
              '@type': 'chat',
              'id': _chatId,
              'title': 'Arrival chat',
              'type': {'@type': 'chatTypePrivate', 'user_id': _peerUserId},
              'permissions': {
                '@type': 'chatPermissions',
                'can_send_basic_messages': true,
              },
              'last_message': _history.last,
            },
            'getUser' => {
              '@type': 'user',
              'id': _peerUserId,
              'first_name': 'Peer',
              'last_name': '',
              'type': {'@type': 'userTypeRegular'},
            },
            'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Me'},
            'getConnectionState' => {'@type': 'connectionStateReady'},
            'getChatHistory' => {
              '@type': 'messages',
              'messages': _history.reversed.toList(),
            },
            'getMessage' => _message(request['message_id'] as int, 'Fetched'),
            _ => {'@type': 'ok'},
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

    Future<void> pumpChat(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      SharedPreferences.setMockInitialValues({
        'showChannelsTab': false,
        'showMomentsTab': false,
        'communitiesEnabled': false,
      });
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
            home: const ChatView(chatId: _chatId, title: 'Arrival chat'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      // The opening sequence positions the viewport across several frames;
      // a live arrival only animates once that has settled.
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    MessageArrival arrivalOf(WidgetTester tester, String text) {
      final row = find.ancestor(
        of: find.text(text, findRichText: true),
        matching: find.byType(MessageArrival),
      );
      expect(row, findsOneWidget, reason: 'row for "$text" is on screen');
      return tester.widget<MessageArrival>(row);
    }

    testWidgets('the initial page opens at rest', (tester) async {
      await pumpChat(tester);
      expect(arrivalOf(tester, 'History hello').animate, isFalse);
      expect(arrivalOf(tester, 'History again').animate, isFalse);
    });

    testWidgets('a live arrival plays the entrance exactly once', (
      tester,
    ) async {
      await pumpChat(tester);
      updates.add({
        '@type': 'updateNewMessage',
        'message': _message(3, 'Live hello'),
      });
      await tester.pump();
      await tester.pump();

      // The row's prop may already have been rebuilt back to false (sender
      // resolution re-syncs the transcript); what matters is that its State
      // is still rising, not that the last widget instance says "arrive".
      arrivalOf(tester, 'Live hello');
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Live hello', findRichText: true),
                matching: find.byType(MessageArrival),
              ),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, lessThan(1));

      // Settled: the wrappers are gone and the row paints at rest.
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Live hello', findRichText: true),
            matching: find.byType(MessageArrival),
          ),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      // A later rebuild of the same row must not restart it.
      updates.add({
        '@type': 'updateMessageContent',
        'chat_id': _chatId,
        'message_id': 3,
        'new_content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'Live hello edited'},
        },
      });
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Live hello edited', findRichText: true),
            matching: find.byType(MessageArrival),
          ),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: 'an edit re-sync is not an arrival',
      );
    });
  });
}
