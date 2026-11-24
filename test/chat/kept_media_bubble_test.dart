//
//  A deleted message's kept copy renders its mirrored media instead of a kind
//  label (Telegram §1.4 self-build feature). Photos paint the snapshot file;
//  other kinds show a file row with the recorded name. The kind label stays
//  the fallback only when no snapshot exists.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/history/message_history_models.dart';
import 'package:mithka/history/message_media_snapshot_view.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = allowTelegramTosViolations;

/// A 1x1 transparent PNG: enough for Image.file to decode in a test.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

MessageHistoryEntry _entry({
  required String kindKey,
  required String mediaPath,
  String text = '',
  String fileName = '',
}) => MessageHistoryEntry(
  accountUserId: 7,
  chatId: 11,
  messageId: 100,
  senderId: 42,
  date: 1700000000,
  text: text,
  kindKey: kindKey,
  state: MessageHistoryState.deleted,
  deletedAt: 1700009999,
  events: const [],
  mediaPath: mediaPath,
  mediaWidth: 1,
  mediaHeight: 1,
  mediaFileName: fileName,
);

ChatMessage _ghost(MessageHistoryEntry entry, {String? text}) => ChatMessage(
  id: entry.messageId,
  isOutgoing: false,
  text: text ?? entry.text,
  date: entry.date,
  chatId: entry.chatId,
  senderId: entry.senderId,
  contentType: 'mithkaGhost',
)..mirrorEntry = entry;

Future<void> _pumpBubble(WidgetTester tester, ChatMessage message) async {
  SharedPreferences.setMockInitialValues(const {});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              MessageBubble(
                message: message,
                peerTitle: 'Peer',
                isGroup: false,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  // The snapshot widget resolves File.exists() asynchronously.
  await tester.pump();
  await tester.pump();
}

void main() {
  if (!_enabled) return;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mithka-kept-media');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  testWidgets('a deleted photo renders its snapshot, not the kind label', (
    tester,
  ) async {
    final file = File('${dir.path}/kept.png')..writeAsBytesSync(_pngBytes);
    final entry = _entry(kindKey: 'historyKindPhoto', mediaPath: file.path);
    await _pumpBubble(tester, _ghost(entry));

    expect(find.byType(MediaSnapshotView), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    // The old placeholder text must be gone now that the media exists.
    expect(find.text('Photo', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a deleted document shows its recorded file name', (
    tester,
  ) async {
    final file = File('${dir.path}/kept.bin')..writeAsBytesSync(const [1, 2]);
    final entry = _entry(
      kindKey: 'historyKindDocument',
      mediaPath: file.path,
      fileName: 'report.pdf',
    );
    await _pumpBubble(tester, _ghost(entry));

    expect(find.text('report.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a ghost without a snapshot keeps the kind label', (
    tester,
  ) async {
    final entry = _entry(kindKey: 'historyKindPhoto', mediaPath: '');
    // The view model substitutes the localized kind label when a media ghost
    // has no snapshot (it is the ghost's whole body).
    await _pumpBubble(tester, _ghost(entry, text: 'Photo'));

    expect(find.byType(MediaSnapshotView), findsNothing);
    // The text bubble paints through RichText, so the finder must look there.
    expect(find.text('Photo', findRichText: true), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
