//
//  auto_translate_loaded_history_test.dart
//
//  "Translate this chat" follows the transcript. Older pages that paging
//  prepends while the user scrolls up must become candidates; the fork used
//  to feed the pass only the newest 32 messages, so every page loaded after
//  the switch was flipped stayed untranslated.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/ai_translation/auto_translate_policy.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _message(int id, {String? translation}) =>
    ChatMessage(id: id, isOutgoing: false, text: 'hello $id', date: id)
      ..translationText = translation
      ..translationLanguageCode = translation == null ? null : 'zh-Hans';

void main() {
  test(
    'an older loaded page is a candidate even when the newest 32 are done',
    () {
      // 60 loaded messages: scrolling up paged 1..30 in after 31..60 existed.
      final loaded = [
        for (var id = 1; id <= 60; id++) _message(id, translation: 'x'),
      ];
      // The newest page (ids 20..60) was translated when it was the window.
      for (var id = 20; id <= 60; id++) {
        loaded[id - 1].translationText = 'translated $id';
      }
      loaded[18].translationText = null; // id 19, outside the old 32 window
      loaded[18].translationLanguageCode = null;

      final candidates = automaticTranslationLoadedCandidates(
        loaded,
        targetLanguageCode: 'zh-Hans',
      );

      expect(
        candidates.map((message) => message.id),
        contains(19),
        reason: 'the page loaded by scrolling up must still be translated',
      );
      // Newest-first: the older page waits behind the untranslated tail.
      expect(candidates.first.id, 19);
    },
  );

  test('messages in the viewport go before the background walk', () {
    final loaded = [for (var id = 1; id <= 40; id++) _message(id)];

    final candidates = automaticTranslationLoadedCandidates(
      loaded,
      targetLanguageCode: 'zh-Hans',
      visibleMessageIds: {2, 5},
    );

    // On-screen messages first (newest-first inside the viewport), then the
    // newest untranslated tail.
    expect(candidates.take(3).map((message) => message.id), [5, 2, 40]);
    expect(candidates.length, 12);
  });

  test('a pass is bounded and continues from the newest end', () {
    final loaded = [for (var id = 1; id <= 40; id++) _message(id)];

    final first = automaticTranslationLoadedCandidates(
      loaded,
      targetLanguageCode: 'zh-Hans',
    );
    expect(first.length, 12);
    expect(first.first.id, 40);
    expect(first.last.id, 29);

    // Once this batch lands, the next pass walks further back instead of
    // stopping at the same window.
    for (final message in first) {
      message.translationText = 'translated';
      message.translationLanguageCode = 'zh-Hans';
    }
    final second = automaticTranslationLoadedCandidates(
      loaded,
      targetLanguageCode: 'zh-Hans',
    );
    expect(second.first.id, 28);
    expect(second.last.id, 17);
  });

  test('failed ids stay out of every later pass', () {
    final loaded = [for (var id = 1; id <= 3; id++) _message(id)];
    final candidates = automaticTranslationLoadedCandidates(
      loaded,
      targetLanguageCode: 'zh-Hans',
      excludedMessageIds: {3},
    );
    expect(candidates.map((message) => message.id), [2, 1]);
  });
}
