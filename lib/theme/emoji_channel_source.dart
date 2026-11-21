//
//  emoji_channel_source.dart
//
//  Emoji font catalog served from the @mithka_metadata Telegram channel —
//  the exteraless-style remote source. A #emojiv2 catalog message holds a
//  JSON body naming each pack's preview and font message ids; fonts are
//  channel documents fetched through the active TDLib account, so no
//  external HTTP host is involved once the client is signed in.
//

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'emoji_font_catalog.dart';

/// The channel that serves the fork's emoji packs.
class EmojiChannelSource {
  EmojiChannelSource({TdClient? client}) : _client = client ?? TdClient.shared;

  static const channelUsername = 'mithka_metadata';
  static const catalogTag = '#emojiv2';

  final TdClient _client;

  /// Cache of chat_id → chat so repeated lookups don't re-resolve the peer.
  int? _cachedChatId;

  /// Resolves the metadata channel to its chat id via searchPublicChat.
  Future<int?> _chatId() async {
    final cached = _cachedChatId;
    if (cached != null) return cached;
    if (!_client.hasActiveClient) return null;
    try {
      final chat = await _client.query({
        '@type': 'searchPublicChat',
        'username': channelUsername,
      }, timeout: const Duration(seconds: 10));
      final id = chat.int64('id');
      if (id == null || id == 0) return null;
      _cachedChatId = id;
      return id;
    } catch (error) {
      debugPrint(
        '[emoji_channel_source] metadata channel lookup failed '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }

  /// Fetches and parses the #emojiv2 catalog into manifest entries. Returns
  /// null when the channel is unreachable (no account / network) so the
  /// caller can fall back to the HTTP manifest.
  Future<List<EmojiFontManifestEntry>?> fetchCatalog() async {
    final chatId = await _chatId();
    if (chatId == null) return null;
    try {
      final response = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': catalogTag,
        'from_message_id': 0,
        'offset': 0,
        'limit': 4,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      }, timeout: const Duration(seconds: 15));
      final messages = response.objects('messages') ?? const [];
      for (final message in messages) {
        final text = message.obj('content')?.obj('text')?.str('text');
        if (text == null || !text.startsWith(catalogTag)) continue;
        final entries = parseCatalog(text);
        if (entries == null) continue;
        return [
          for (final entry in entries)
            EmojiFontManifestEntry(
              key: entry.key,
              label: entry.label,
              license: entry.license,
              chatId: chatId,
              channelMessageId: entry.channelMessageId,
              channelPreviewMessageId: entry.channelPreviewMessageId,
              sizeBytes: entry.sizeBytes,
            ),
        ];
      }
      return null;
    } catch (error) {
      debugPrint(
        '[emoji_channel_source] catalog search failed '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }

  /// Catalog text is `<tag>\n{json}` — the same body the exteraless helper
  /// parses. Mapped onto [EmojiFontManifestEntry]s with the channel message
  /// id kept as the download address; chatId is left 0 for fetchCatalog to
  /// stamp once the channel is known.
  @visibleForTesting
  static List<EmojiFontManifestEntry>? parseCatalog(String body) {
    final jsonStart = body.indexOf('{');
    if (jsonStart < 0) return null;
    final decoded = jsonDecode(body.substring(jsonStart));
    if (decoded is! Map) return null;
    final emojis = decoded['emojis'];
    if (emojis is! List) return null;
    final entries = <EmojiFontManifestEntry>[];
    for (final item in emojis) {
      if (item is! Map) continue;
      final key = (item['id'] as String?)?.trim() ?? '';
      final label = (item['name'] as String?)?.trim() ?? '';
      final file = (item['file'] as num?)?.toInt();
      final size = (item['size'] as num?)?.toInt();
      final preview = (item['preview'] as num?)?.toInt();
      if (key.isEmpty || label.isEmpty || file == null || file <= 0) continue;
      entries.add(
        EmojiFontManifestEntry(
          key: key,
          label: label,
          license: (item['license'] as String?)?.trim() ?? '',
          chatId: 0,
          channelMessageId: file,
          channelPreviewMessageId: (preview != null && preview > 0)
              ? preview
              : null,
          sizeBytes: size,
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }

  /// Downloads a pack's font file (a .ttf document in the channel) to
  /// [destPath]. Returns the byte length, or null on any failure.
  ///
  /// The document's `mime_type` is deliberately not pinned: Telegram serves
  /// the same .ttf as `font/ttf`, `application/x-font-ttf` or
  /// `application/octet-stream` depending on the uploader's client, and a
  /// `font/` prefix check rejected every real-device download. The pack's
  /// byte size is verified later by [EmojiFontCatalog.ensureFontDownloaded],
  /// so a wrong-kind file can't register as a broken family here.
  Future<int?> downloadFont({
    required int chatId,
    required int messageId,
    required String destPath,
  }) => _downloadChannelDocument(
    chatId: chatId,
    messageId: messageId,
    destPath: destPath,
    expectedMimeType: '',
  );

  /// Downloads a pack's preview image (a PNG document in the channel) to
  /// [destPath]. Returns the byte length, or null on any failure — the
  /// caller falls back to a bundled asset.
  Future<int?> downloadPreview({
    required int chatId,
    required int messageId,
    required String destPath,
  }) => _downloadChannelDocument(
    chatId: chatId,
    messageId: messageId,
    destPath: destPath,
    expectedMimeType: 'image/',
  );

  /// Shared message → document → downloadFile pipeline for both font and
  /// preview documents. [expectedMimeType] rejects wrong-kind messages (a
  /// font where a preview should be, and vice versa).
  ///
  /// downloadFile is fired with synchronous: false, then getFile is polled
  /// until is_downloading_completed flips true — mirroring td_image_loader's
  /// pattern. synchronous: true on real devices can report incomplete even
  /// when the transfer is in flight, which made every pack download fail.
  /// Runs the real download pipeline step by step and returns a human-readable
  /// report. Used by the in-app diagnostics dialog when a tester cannot attach
  /// adb — every failure point is reported with the concrete TDLib error.
  Future<String> diagnose() async {
    final out = <String>[];
    void log(String s) => out.add(s);
    String err(Object e) =>
        e is TdError ? 'TdError ${e.code}: ${e.message}' : '$e';

    log('=== emoji channel diagnostics ${DateTime.now().toIso8601String()} ===');
    log(
      'client: hasActiveClient=${_client.hasActiveClient} '
      'activeClientId=${_client.activeClientId} slot=${_client.activeSlot}',
    );
    if (!_client.hasActiveClient) {
      log('RESULT: no active TDLib client — downloads cannot start');
      return out.join('\n');
    }

    int? chatId;
    try {
      final chat = await _client.query({
        '@type': 'searchPublicChat',
        'username': channelUsername,
      }, timeout: const Duration(seconds: 10));
      chatId = chat.int64('id');
      log(
        'searchPublicChat: OK id=$chatId title=${chat.str('title')} '
        'type=${chat.obj('type')?.str('@type')}',
      );
    } catch (e) {
      log('searchPublicChat: FAILED ${err(e)}');
      return out.join('\n');
    }
    if (chatId == null || chatId == 0) {
      log('RESULT: channel id is zero');
      return out.join('\n');
    }

    List<EmojiFontManifestEntry>? entries;
    try {
      final response = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': catalogTag,
        'from_message_id': 0,
        'offset': 0,
        'limit': 4,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      }, timeout: const Duration(seconds: 15));
      final messages = response.objects('messages') ?? const [];
      log('searchChatMessages: OK messages=${messages.length}');
      for (final m in messages) {
        final text = m.obj('content')?.obj('text')?.str('text');
        if (text == null || !text.startsWith(catalogTag)) continue;
        entries = parseCatalog(text);
        log(
          'catalog: messageId=${m.int64('id')} textLen=${text.length} '
          'entries=${entries?.length ?? 0}',
        );
        break;
      }
      if (entries == null || entries.isEmpty) {
        log('RESULT: no parseable #emojiv2 catalog message');
        return out.join('\n');
      }
      final first = entries.first;
      log(
        'first entry: key=${first.key} fontMsgId=${first.channelMessageId} '
        'previewMsgId=${first.channelPreviewMessageId} '
        'size=${first.sizeBytes}',
      );
    } catch (e) {
      log('searchChatMessages: FAILED ${err(e)}');
      return out.join('\n');
    }

    final entry = entries.first;
    Future<int?> inspect(String label, int messageId, String wantMime) async {
      final tdMessageId = toTdlibMessageId(messageId);
      try {
        final response = await _client.query({
          '@type': 'getMessages',
          'chat_id': chatId,
          'message_ids': [tdMessageId],
        }, timeout: const Duration(seconds: 15));
        final list = response.objects('messages') ?? const [];
        log(
          '$label getMessages(server=$messageId td=$tdMessageId): '
          'OK messages=${list.length}',
        );
        Map<String, dynamic>? message;
        for (final m in list) {
          if (m.int64('id') == tdMessageId) message = m;
        }
        if (message == null) {
          log('$label: message id not present in response');
          return null;
        }
        final content = message.obj('content');
        final document = content?.obj('document');
        final file = document?.obj('document');
        log(
          '$label content type=${content?.str('@type')} '
          'doc=${document == null ? 'null' : 'present'} '
          'mime=${document?.str('mime_type')} '
          'size=${file?.int64('size')}',
        );
        if (document == null) {
          log('$label: content has no document');
          return null;
        }
        final fileId = file?.int64('id');
        log('$label document.document.id=$fileId');
        if (fileId == null || fileId == 0) return null;
        return fileId;
      } catch (e) {
        log('$label getMessages FAILED ${err(e)}');
        return null;
      }
    }

    final fontFileId = await inspect('FONT', entry.channelMessageId, 'font/');
    final previewMessageId = entry.channelPreviewMessageId;
    final previewFileId = previewMessageId == null
        ? null
        : await inspect('PREVIEW', previewMessageId, 'image/');

    Future<void> downloadProbe(String label, int? fileId, int limit) async {
      if (fileId == null) {
        log('$label: no file id, skipping download probe');
        return;
      }
      try {
        final response = await _client.query({
          '@type': 'downloadFile',
          'file_id': fileId.toString(),
          'priority': 32,
          'offset': 0,
          'limit': limit,
          'synchronous': false,
        }, timeout: const Duration(seconds: 10));
        if (response.str('@type') == 'error') {
          log('$label downloadFile FAILED ${err(TdError(response))}');
          return;
        }
        log(
          '$label downloadFile OK type=${response.str('@type')} '
          'local=${response.obj('local') == null ? 'null' : 'present'}',
        );
      } catch (e) {
        log('$label downloadFile FAILED ${err(e)}');
        return;
      }
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          final info = await _client.query({
            '@type': 'getFile',
            'file_id': fileId.toString(),
          }, timeout: const Duration(seconds: 10));
          final local = info.obj('local');
          log(
            '$label getFile[$i]: done=${local?.boolean('is_downloading_completed')} '
            'active=${local?.boolean('is_downloading_active')} '
            'size=${local?.int64('downloaded_size')} '
            'prefix=${local?.int64('downloaded_prefix_size')} '
            'path=${local?.str('path') ?? ''}',
          );
          if (local?.boolean('is_downloading_completed') == true) return;
        } catch (e) {
          log('$label getFile[$i] FAILED ${err(e)}');
          return;
        }
      }
    }

    // 1 byte proves the file id without pulling the whole pack; the preview is
    // small enough to download for real.
    await downloadProbe('FONT', fontFileId, 1);
    await downloadProbe('PREVIEW', previewFileId, 0);

    log('RESULT: report complete');
    return out.join('\n');
  }

  /// TDLib stores supergroup/channel message ids as `server_id << 20`; the
  /// catalog text carries the plain server ids (file: 23 → TDLib 24117248).
  /// Passing the server id straight to getMessages yields TdError 400
  /// "Invalid message identifier" and every download silently fails.
  static const _channelMessageIdShift = 20;

  @visibleForTesting
  static int toTdlibMessageId(int channelMessageId) =>
      channelMessageId << _channelMessageIdShift;

  /// Shared message → document → downloadFile pipeline for both font and
  /// preview documents. [expectedMimeType] rejects wrong-kind messages (a
  /// font where a preview should be, and vice versa).
  Future<int?> _downloadChannelDocument({
    required int chatId,
    required int messageId,
    required String destPath,
    required String expectedMimeType,
  }) async {
    final tdMessageId = toTdlibMessageId(messageId);
    try {
      final messages = await _client.query({
        '@type': 'getMessages',
        'chat_id': chatId,
        'message_ids': [tdMessageId],
      }, timeout: const Duration(seconds: 15));
      final list = messages.objects('messages') ?? const [];
      Map<String, dynamic>? message;
      for (final candidate in list) {
        if (candidate.int64('id') == tdMessageId) message = candidate;
      }
      if (message == null) {
        debugPrint(
          '[emoji_channel_source] message missing chatId=$chatId '
          'serverMsgId=$messageId tdMsgId=$tdMessageId returned=${list.length} '
          'responseType=${messages.str('@type')}',
        );
        return null;
      }
      final document = message.obj('content')?.obj('document');
      // TDLib's document object keeps the download file one level deeper:
      // content.document is the `document`, and content.document.document is
      // the `file` carrying id/size. Reading document.id yields null (the
      // teleproto probe that suggested a flat shape was a different JSON
      // schema), so every download skipped with "no file id".
      final file = document?.obj('document');
      final fileId = file?.int64('id');
      if (fileId == null || fileId == 0) {
        debugPrint(
          '[emoji_channel_source] no fileId for chatId=$chatId msgId=$messageId '
          'document=${jsonEncode(document)}',
        );
        return null;
      }
      final mime = document?.str('mime_type') ?? '';
      if (expectedMimeType.isNotEmpty && !mime.startsWith(expectedMimeType)) {
        debugPrint(
          '[emoji_channel_source] mime mismatch chatId=$chatId msgId=$messageId '
          'expected=$expectedMimeType actual=$mime',
        );
        return null;
      }

      final downloadResponse = await _client.query({
        '@type': 'downloadFile',
        // TDLib JSON API transports int64 fields as strings to avoid precision
        // loss on large file ids (e.g. 6046350849301554328 > 2^53). Sending a
        // raw Dart int through JSON would round-trip through a double and
        // corrupt the id, making downloadFile fail silently.
        'file_id': fileId.toString(),
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      }, timeout: const Duration(seconds: 10));
      // A failed downloadFile (error response) means the pack can't be
      // fetched — bail out immediately instead of polling getFile for up to
      // nine minutes before surfacing a "download failed" error.
      if (downloadResponse.str('@type') == 'error') {
        debugPrint(
          '[emoji_channel_source] downloadFile error chatId=$chatId msgId=$messageId '
          'fileId=$fileId response=${jsonEncode(downloadResponse)}',
        );
        return null;
      }
      debugPrint(
        '[emoji_channel_source] downloadFile accepted chatId=$chatId '
        'msgId=$messageId fileId=$fileId '
        'responseType=${downloadResponse.str('@type')}',
      );

      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(minutes: 9)) {
        await Future.delayed(const Duration(seconds: 2));
        final fileInfo = await _client.query({
          '@type': 'getFile',
          'file_id': fileId.toString(),
        }, timeout: const Duration(seconds: 10));
        final local = fileInfo.obj('local');
        final done = local?.boolean('is_downloading_completed') == true;
        final path = local?.str('path');
        debugPrint(
          '[emoji_channel_source] getFile poll msgId=$messageId '
          'done=$done path=${path ?? ''} '
          'downloaded=${local?.int64('downloaded_prefix_size') ?? 0} '
          'size=${local?.int64('downloaded_size') ?? 0}',
        );
        if (done && path != null && path.isNotEmpty) {
          final src = File(path);
          if (await src.exists()) {
            final dst = File(destPath);
            await dst.parent.create(recursive: true);
            await src.copy(destPath);
            return await dst.length();
          }
        }
      }
      return null;
    } catch (error) {
      final detail = error is TdError
          ? 'code=${error.code} message=${error.message}'
          : '$error';
      debugPrint(
        '[emoji_channel_source] document download failed '
        'type=${error.runtimeType} $detail',
      );
      return null;
    }
  }
}
