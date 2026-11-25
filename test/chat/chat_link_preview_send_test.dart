import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/links_search/link_preview_fixer.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chatId = 42;

/// A TDLib `textEntity` over [text], used to keep a formatted span out of the
/// link scan.
Map<String, dynamic> _codeEntity(String text) => {
  '@type': 'textEntity',
  'offset': 0,
  'length': text.length,
  'type': {'@type': 'textEntityTypeCode'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> requests;

  setUpAll(() {
    // In-memory transport only: these tests never touch a Telegram account.
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          if (request['@type'] == 'sendMessage') {
            return {'@type': 'message', 'id': 99};
          }
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
  });
  tearDownAll(TdClient.shared.closeProxy);

  setUp(() async {
    requests = [];
    SharedPreferences.setMockInitialValues({});
    LinkPreviewFixer.shared.initialize(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await LinkPreviewFixer.shared.setEnabled(false);
  });

  Future<void> enableFixer() async {
    SharedPreferences.setMockInitialValues({
      LinkPreviewFixer.preferenceKey: true,
    });
    LinkPreviewFixer.shared.initialize(await SharedPreferences.getInstance());
  }

  ChatViewModel model() {
    final vm = ChatViewModel(
      chatId: _chatId,
      title: 'Preview',
      markReadOnOpen: false,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  Map<String, dynamic> sentContent() {
    final sent = requests
        .where((request) => request['@type'] == 'sendMessage')
        .single;
    return Map<String, dynamic>.from(
      sent['input_message_content'] as Map<String, dynamic>,
    );
  }

  test(
    'an opted-in send keeps the text and points the preview at a mirror',
    () async {
      await enableFixer();
      final vm = model()..setDraft('看 https://x.com/user/status/1 这个');

      expect(await vm.send(), isTrue);

      final content = sentContent();
      expect(content['text'], {
        '@type': 'formattedText',
        'text': '看 https://x.com/user/status/1 这个',
      });
      expect(content['link_preview_options'], {
        '@type': 'linkPreviewOptions',
        'is_disabled': false,
        'url': 'https://fixupx.com/user/status/1',
      });
    },
  );

  test('a formatted send skips a link the sender put in code', () async {
    await enableFixer();
    const coded = 'https://x.com/user/status/1';
    final vm = model();

    expect(
      await vm.sendFormatted('$coded 以及 https://twitter.com/user/status/2', [
        _codeEntity(coded),
      ]),
      isTrue,
    );

    // The code span does not claim the preview slot, so the visible Twitter
    // link is the first one TDLib would preview — and it has a mirror.
    final content = sentContent();
    expect(content['link_preview_options'], {
      '@type': 'linkPreviewOptions',
      'is_disabled': false,
      'url': 'https://fxtwitter.com/user/status/2',
    });
  });

  group('mirror table matches the exteraless page-preview rules', () {
    const rules = {
      'https://x.com/user/status/1': 'https://fixupx.com/user/status/1',
      'https://twitter.com/user/status/1':
          'https://fxtwitter.com/user/status/1',
      'https://coolapk.com/feed/1': 'https://coolapk1s.com/feed/1',
      'https://www.instagram.com/p/abc/': 'https://kkinstagram.com/p/abc/',
      'https://vm.tiktok.com/ZMabc/': 'https://vm.kktiktok.com/ZMabc/',
      'https://vt.tiktok.com/ZSabc/': 'https://vt.kktiktok.com/ZSabc/',
      'https://www.tiktok.com/@user/video/1':
          'https://www.kktiktok.com/@user/video/1',
      'https://www.reddit.com/r/aww/comments/1/title/':
          'https://www.rxddit.com/r/aww/comments/1/title/',
      'https://bsky.app/profile/user/post/1':
          'https://fxbsky.app/profile/user/post/1',
      'https://www.pixiv.net/artworks/1': 'https://www.phixiv.net/artworks/1',
    };

    for (final rule in rules.entries) {
      test(rule.key, () {
        expect(LinkPreviewFixer.fixedUrl(rule.key), rule.value);
        // The send path and the host table agree on the same rewrite.
        expect(
          LinkPreviewFixer.previewHosts[Uri.parse(rule.key).host],
          isNotNull,
        );
      });
    }

    test('a site without a rule is left alone', () {
      expect(LinkPreviewFixer.fixedUrl('https://example.com/post/1'), isNull);
    });
  });

  test('the fix is on out of the box, like exteraless', () async {
    final vm = model()..setDraft('https://x.com/user/status/1');

    expect(LinkPreviewFixer.shared.enabled, isTrue);
    expect(await vm.send(), isTrue);

    expect(sentContent()['link_preview_options'], {
      '@type': 'linkPreviewOptions',
      'is_disabled': false,
      'url': 'https://fixupx.com/user/status/1',
    });
  });

  test('turning the switch off leaves the send alone', () async {
    await LinkPreviewFixer.shared.setEnabled(false);
    final vm = model()..setDraft('https://x.com/user/status/1');

    expect(await vm.send(), isTrue);

    expect(sentContent().containsKey('link_preview_options'), isFalse);
  });
}
