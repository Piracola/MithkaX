//
//  chat_translate_all_visibility_test.dart
//
//  The chat-level "translate to <language>" command is a promise that the
//  transcript will change. Offer it only when the chat's language is known and
//  differs from the target, like exteraless: a chat already in the target
//  language, or one whose language is still unknown, carries no Translate
//  entry in its header menu (and no suggestion bar).
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/components/drawer_controller.dart' as dc;
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 771002;
const _peerUserId = 7711;

const _translationChannel = MethodChannel('mithka/native_translation');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<Map<String, dynamic>> updates;
  String? detectedLanguage;
  String messageText = '';

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getChat' => {
            '@type': 'chat',
            'id': _chatId,
            'title': 'Language chat',
            'type': {'@type': 'chatTypePrivate', 'user_id': _peerUserId},
            'permissions': {
              '@type': 'chatPermissions',
              'can_send_basic_messages': true,
            },
            'last_read_inbox_message_id': 1,
          },
          'getUser' || 'getMe' => {
            '@type': 'user',
            'id': request['user_id'] ?? _peerUserId,
            'first_name': 'Ann',
            'type': {'@type': 'userTypeRegular'},
          },
          'getChatHistory' => {
            '@type': 'messages',
            'total_count': 1,
            'messages': [
              {
                '@type': 'message',
                'id': 10,
                'chat_id': _chatId,
                'date': 1785862260,
                'is_outgoing': false,
                'sender_id': {
                  '@type': 'messageSenderUser',
                  'user_id': _peerUserId,
                },
                'content': {
                  '@type': 'messageText',
                  'text': {'@type': 'formattedText', 'text': messageText},
                },
                'reply_to': {'@type': 'messageReplyToMessage', 'chat_id': 0},
              },
            ],
          },
          'getOption' => {'@type': 'optionValueInteger', 'value': '1024'},
          'getCountries' => {'@type': 'countries', 'countries': const []},
          'getCurrentState' => {'@type': 'ok'},
          'getBotApiAccountInfo' => {'@type': 'ok'},
          _ => {'@type': 'ok'},
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
    ChatHeaderStateCache.resetForTesting();
    detectedLanguage = null;
    messageText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_translationChannel, (call) async {
          return switch (call.method) {
            'capabilities' => <String>[],
            'identifyLanguage' =>
              detectedLanguage == null
                  ? null
                  : {'languageCode': detectedLanguage, 'confidence': 0.9},
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_translationChannel, null);
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
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: [AppColors.light],
          ),
          home: const ChatView(chatId: _chatId, title: 'Language chat'),
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

  Finder translateRow() =>
      find.byKey(const ValueKey('app-anchored-menu-translate'));

  testWidgets('a chat already in the target language offers no translate-all', (
    tester,
  ) async {
    detectedLanguage = 'zh-Hans';
    messageText = '这是一条完全用中文写成的消息，用来让语言识别返回中文。';
    await openChat(tester);

    expect(
      find.byKey(const ValueKey('chat-translation-panel')),
      findsNothing,
      reason: 'no suggestion bar in a chat that needs no translation',
    );
    await openMenu(tester);
    expect(translateRow(), findsNothing);
    await closeChat(tester);
  });

  testWidgets('a foreign-language chat offers translate-all and the bar', (
    tester,
  ) async {
    detectedLanguage = 'en';
    messageText = 'This message is written in English so detection says so.';
    await openChat(tester);

    expect(
      find.byKey(const ValueKey('chat-translation-panel')),
      findsOneWidget,
    );
    await openMenu(tester);
    expect(translateRow(), findsOneWidget);
    await closeChat(tester);
  });

  testWidgets('an unknown chat language does not invent a translate-all', (
    tester,
  ) async {
    detectedLanguage = null;
    messageText = '12345 67890 12345 67890 12345';
    await openChat(tester);

    expect(find.byKey(const ValueKey('chat-translation-panel')), findsNothing);
    await openMenu(tester);
    expect(translateRow(), findsNothing);
    await closeChat(tester);
  });
}
