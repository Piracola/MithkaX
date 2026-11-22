//
//  topic_close_rights_test.dart
//
//  Closing a topic is offered wherever the server accepts it: a
//  can_manage_topics administrator, or the topic's own creator (TDLib's
//  carve-out). The General topic never closes, and a chat with a topics bot
//  has no close call at all — its toggleForumTopicIsClosed is supergroup-only.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatViewModel model({bool forum = true}) =>
      ChatViewModel(chatId: -1001, title: 'Forum', markReadOnOpen: false)
        ..isForum = forum
        ..supportsBotTopics = !forum;

  test('an administrator closes any non-General topic', () {
    final viewModel = model()
      ..canManageTopics = true
      ..meId = 7;
    addTearDown(viewModel.dispose);

    expect(
      viewModel.canCloseTopic(const ForumTopicOption(id: 5, name: 'A')),
      isTrue,
    );
    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 1, name: 'General', isGeneral: true),
      ),
      isFalse,
    );
  });

  test('a topic creator closes their own topic without admin rights', () {
    final viewModel = model()..meId = 7;
    addTearDown(viewModel.dispose);

    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 7),
      ),
      isTrue,
    );
    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 9),
      ),
      isFalse,
    );
  });

  test('a chat with a topics bot never closes topics', () {
    final viewModel = model(forum: false)
      ..canManageTopics = true
      ..meId = 7;
    addTearDown(viewModel.dispose);

    expect(
      viewModel.canCloseTopic(
        const ForumTopicOption(id: 5, name: 'A', creatorId: 7),
      ),
      isFalse,
    );
  });
}
