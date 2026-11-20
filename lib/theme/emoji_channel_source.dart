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
  Future<int?> _downloadChannelDocument({
    required int chatId,
    required int messageId,
    required String destPath,
    required String expectedMimeType,
  }) async {
    try {
      final messages = await _client.query({
        '@type': 'getMessages',
        'chat_id': chatId,
        'message_ids': [messageId],
      }, timeout: const Duration(seconds: 15));
      final list = messages.objects('messages') ?? const [];
      Map<String, dynamic>? message;
      for (final candidate in list) {
        if (candidate.int64('id') == messageId) message = candidate;
      }
      if (message == null) return null;
      final document = message.obj('content')?.obj('document');
      // TDLib's messageDocument nests the file under document.document:
      // content.document is the descriptor (mime_type, size…), the download
      // id lives on content.document.document (the file object). Taking the
      // descriptor's own id always yielded null and every pack download
      // failed — the extra .obj('document') layer is required, not optional.
      final fileId = document?.obj('document')?.int64('id');
      if (fileId == null || fileId == 0) return null;
      final mime = document?.str('mime_type') ?? '';
      if (expectedMimeType.isNotEmpty && !mime.startsWith(expectedMimeType)) return null;

      final downloadResponse = await _client.query({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      }, timeout: const Duration(seconds: 10));
      // A failed downloadFile (error response) means the pack can't be
      // fetched — bail out immediately instead of polling getFile for up to
      // nine minutes before surfacing a "download failed" error.
      if (downloadResponse.str('@type') == 'error') return null;

      final stopwatch = Stopwatch()..start();
      while (stopwatch.elapsed < const Duration(minutes: 9)) {
        await Future.delayed(const Duration(seconds: 2));
        final fileInfo = await _client.query({
          '@type': 'getFile',
          'file_id': fileId,
        }, timeout: const Duration(seconds: 10));
        final local = fileInfo.obj('local');
        final done = local?.boolean('is_downloading_completed') == true;
        final path = local?.str('path');
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
      debugPrint(
        '[emoji_channel_source] document download failed '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }
}
