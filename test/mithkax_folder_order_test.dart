import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_folder_tab_menu.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/chat_folder_management_view.dart';
import 'package:mithka/settings/chat_folder_service.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The folder order surfaces must stay usable with many folders and must show
// what Telegram actually stores: the main list's own position and each
// folder's icon.

ChatFolderRecord folderRecord(int id, String title, {String icon = 'Custom'}) =>
    ChatFolderRecord(
      id: id,
      title: title,
      raw: {
        '@type': 'chatFolder',
        'name': {
          '@type': 'chatFolderName',
          'text': {'@type': 'formattedText', 'text': title},
        },
        'icon': {'@type': 'chatFolderIcon', 'name': icon},
      },
      hasInviteLinks: false,
    );

ChatFolderService recordingService(List<Map<String, dynamic>> sent) =>
    ChatFolderService(
      query: (request) async {
        sent.add(request);
        return {'@type': 'ok'};
      },
    );

Widget appShell(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(extensions: [AppColors.light]),
  home: Scaffold(body: home),
);

void main() {
  testWidgets('a long folder order sheet scrolls from the row body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2100);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final folders = [
      for (var id = 1; id <= 24; id++) folderRecord(id, 'Folder $id'),
    ];
    await tester.pumpWidget(
      appShell(
        ChatFolderReorderSheet(
          folders: folders,
          mainListPosition: 0,
          service: recordingService(<Map<String, dynamic>>[]),
        ),
      ),
    );

    expect(find.text('Folder 24'), findsNothing);
    // The row body must belong to the scroll view, not to a drag listener;
    // dragging it used to start a reorder instead of scrolling.
    expect(
      find.descendant(
        of: find.byType(ReorderableDragStartListener),
        matching: find.text('Folder 1'),
      ),
      findsNothing,
      reason: 'only the grip may start a reorder',
    );

    await tester.drag(
      find.byKey(const ValueKey('chat-folder-order-main')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();

    expect(find.text('Folder 24'), findsOneWidget);
  });

  testWidgets('the order sheet draws each folder\'s own icon', (tester) async {
    final folders = [
      folderRecord(7, 'Business', icon: 'Cat'),
      folderRecord(8, 'Home', icon: 'Home'),
    ];
    await tester.pumpWidget(
      appShell(
        ChatFolderReorderSheet(
          folders: folders,
          mainListPosition: 0,
          service: recordingService(<Map<String, dynamic>>[]),
        ),
      ),
    );

    final names = tester
        .widgetList<ChatFolderIcon>(find.byType(ChatFolderIcon))
        .map((icon) => icon.name)
        .toList();
    expect(names, ['All', 'Cat', 'Home']);
  });

  testWidgets('settings rows draw each folder\'s own icon', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final updates = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(updates.close);

    final service = ChatFolderService(
      query: (request) async {
        if (request['@type'] == 'getChatFolder') {
          final id = request['chat_folder_id'] as int;
          return {
            '@type': 'chatFolder',
            'id': id,
            'name': {
              '@type': 'chatFolderName',
              'text': {'@type': 'formattedText', 'text': 'Folder $id'},
            },
            'icon': {
              '@type': 'chatFolderIcon',
              'name': id == 7 ? 'Cat' : 'Home',
            },
          };
        }
        if (request['@type'] == 'getRecommendedChatFolders') {
          return {'@type': 'chatFolders', 'chat_folders': <Object>[]};
        }
        return {'@type': 'ok'};
      },
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppColors.light]),
          home: ChatFolderManagementView(
            service: service,
            updates: updates.stream,
          ),
        ),
      ),
    );
    await tester.pump();
    updates.add({
      '@type': 'updateChatFolders',
      'chat_folders': [
        {'id': 7, 'title': 'Folder 7'},
        {'id': 8, 'title': 'Folder 8'},
      ],
      'main_chat_list_position': 0,
    });
    await tester.pumpAndSettle();

    final names = tester
        .widgetList<ChatFolderIcon>(find.byType(ChatFolderIcon))
        .map((icon) => icon.name)
        .toList();
    expect(names, ['Cat', 'Home']);
  });
}
