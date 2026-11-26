//
//  Channel posts read like exteraless's wide channel posts: no repeated 38pt
//  author column beside every post; a compact channel avatar + title ride
//  above the bubble instead, leaving the post the full lane.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_bubble.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage _post() => ChatMessage(
  id: 42,
  isOutgoing: false,
  text: 'A channel post',
  date: 1700000000,
  chatId: -100123,
  senderName: 'Daily News',
  contentType: 'messageText',
);

Future<void> _pump(WidgetTester tester, {required bool isChannel}) async {
  SharedPreferences.setMockInitialValues(const {});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _post(),
            peerTitle: 'Daily News',
            isGroup: true,
            isChannel: isChannel,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a channel post has one compact author avatar', (tester) async {
    await _pump(tester, isChannel: true);
    final avatars = tester.widgetList<PhotoAvatar>(find.byType(PhotoAvatar));
    expect(avatars, hasLength(1));
    expect(avatars.single.size, 20);
    expect(
      find.byKey(const ValueKey('messageSenderHeader-42')),
      findsOneWidget,
    );
    expect(find.text('Daily News', findRichText: true), findsOneWidget);
  });

  testWidgets('a group message keeps the 38pt side avatar', (tester) async {
    await _pump(tester, isChannel: false);
    final avatars = tester.widgetList<PhotoAvatar>(find.byType(PhotoAvatar));
    expect(avatars, hasLength(1));
    expect(avatars.single.size, 38);
  });
}
