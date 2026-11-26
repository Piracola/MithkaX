//
//  l10n_channel_direct_messages_test.dart
//
//  The channel header's direct-messages row used to stay English in every
//  locale: the key existed in all eight catalogues with an English value.
//

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, String>> catalogue(String tag) async {
    final raw = await rootBundle.loadString('assets/l10n/$tag.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return (json['strings'] as Map<String, dynamic>).cast<String, String>();
  }

  test('the direct-messages menu row is translated in every locale', () async {
    expect((await catalogue('zh-Hans-CN'))['channelDirectMessages'], '频道私聊');
    expect((await catalogue('zh-Hant-TW'))['channelDirectMessages'], '頻道私聊');
    expect(
      (await catalogue('de-DE'))['channelDirectMessages'],
      'Kanal-Direktnachrichten',
    );
    expect(
      (await catalogue('es-ES'))['channelDirectMessages'],
      'Mensajes directos del canal',
    );
    expect(
      (await catalogue('fr-FR'))['channelDirectMessages'],
      'Messages privés de la chaîne',
    );
    expect(
      (await catalogue('ja-JP'))['channelDirectMessages'],
      'チャンネルのダイレクトメッセージ',
    );
    expect((await catalogue('ko-KR'))['channelDirectMessages'], '채널 다이렉트 메시지');
    expect(
      (await catalogue('en-US'))['channelDirectMessages'],
      'Channel Direct Messages',
    );
  });
}
