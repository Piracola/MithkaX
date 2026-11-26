//
//  pinned_messages_view.dart
//
//  The pinned-message browser behind a long press on the chat's pinned bar.
//  It is the reference client's MODE_PINNED transcript: the pinned messages as
//  ordinary chat bubbles under a "N Pinned Messages" title, with a bottom bar
//  that unpins them all (or hides the bar when this account may not unpin).
//  Tapping a bubble closes the page and asks the open chat to jump there.
//

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../app/ipad_window_chrome.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'messages/message_bubble.dart';

/// What the pinned list asks the chat to do when it closes without a target.
enum PinnedMessagesExit { hide }

/// One row of the pinned transcript: a date chip or a message.
sealed class _PinnedEntry {
  const _PinnedEntry();
}

class _PinnedDateEntry extends _PinnedEntry {
  const _PinnedDateEntry(this.date);
  final DateTime date;
}

class _PinnedMessageEntry extends _PinnedEntry {
  const _PinnedMessageEntry(this.message);
  final ChatMessage message;
}

class PinnedMessagesView extends StatefulWidget {
  const PinnedMessagesView({
    super.key,
    required this.chatId,
    required this.title,
  });

  final int chatId;
  final String title;

  @override
  State<PinnedMessagesView> createState() => _PinnedMessagesViewState();
}

class _PinnedMessagesViewState extends State<PinnedMessagesView> {
  final TdClient _client = TdClient.shared;
  late final int _accountSlot;
  final Map<int, String> _names = {};
  final Map<int, TdFileRef?> _photos = {};
  bool _loading = true;
  bool _unpinning = false;
  bool _canPin = false;
  bool _isGroup = false;
  TdFileRef? _chatPhoto;
  String _meName = '';
  TdFileRef? _mePhoto;
  int? _meId;
  List<ChatMessage> _items = [];

  @override
  void initState() {
    super.initState();
    _accountSlot = _client.activeSlot;
    _meName = AppStrings.t(AppStringKeys.chatMeLabel);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _client.queryForSlot({
        '@type': 'searchChatMessages',
        'chat_id': widget.chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 100,
        'filter': {'@type': 'searchMessagesFilterPinned'},
      }, _accountSlot);
      final list = res.objects('messages') ?? const <Map<String, dynamic>>[];
      final chat = await _client.queryForSlot({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      }, _accountSlot);
      final kind = TDParse.chatKind(chat);
      final isChannel = kind == ChatKind.channel;
      final parsed = list
          .map((raw) => TDParse.message(raw, isChannel: isChannel))
          .whereType<ChatMessage>()
          .toList();
      for (final message in parsed) {
        await _resolveSender(message);
      }
      var meName = AppStrings.t(AppStringKeys.chatMeLabel);
      TdFileRef? mePhoto;
      int? meId;
      try {
        final me = await _client.queryForSlot({'@type': 'getMe'}, _accountSlot);
        meId = me.int64('id');
        meName = TDParse.userName(me);
        mePhoto = TDParse.smallPhoto(me.obj('profile_photo'));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _items = parsed;
        _chatPhoto = TDParse.smallPhoto(chat.obj('photo'));
        _isGroup = kind != ChatKind.privateChat && kind != ChatKind.bot;
        _canPin = chat.obj('permissions')?.boolean('can_pin_messages') ?? false;
        _meName = meName;
        _mePhoto = mePhoto;
        _meId = meId;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolveSender(ChatMessage message) async {
    final id = message.senderId;
    if (id == null) return;
    if (!_names.containsKey(id)) {
      try {
        if (id > 0) {
          final user = await _client.queryForSlot({
            '@type': 'getUser',
            'user_id': id,
          }, _accountSlot);
          _names[id] = TDParse.userName(user);
          _photos[id] = TDParse.smallPhoto(user.obj('profile_photo'));
        } else {
          final chat = await _client.queryForSlot({
            '@type': 'getChat',
            'chat_id': id,
          }, _accountSlot);
          _names[id] = chat.str('title') ?? widget.title;
          _photos[id] = TDParse.smallPhoto(chat.obj('photo'));
        }
      } catch (_) {
        _names[id] = widget.title;
        _photos[id] = null;
      }
    }
    message.senderName = _names[id] ?? message.senderName;
    message.senderPhoto = _photos[id];
  }

  Future<void> _unpinAll() async {
    if (_unpinning) return;
    setState(() => _unpinning = true);
    try {
      await _client.queryForSlot({
        '@type': 'unpinAllChatMessages',
        'chat_id': widget.chatId,
      }, _accountSlot);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _unpinning = false);
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatInfoPinFailedWithReason, {
          'value1': error,
        }),
      );
    }
  }

  void _jumpTo(ChatMessage message) => Navigator.of(context).pop(message.id);

  void _hideBar() => Navigator.of(context).pop(PinnedMessagesExit.hide);

  /// Oldest first, one date chip above the first message of each day; the list
  /// is painted reversed so the newest message sits at the bottom — the
  /// transcript order the reference client loads in MODE_PINNED.
  List<_PinnedEntry> _entries() {
    final chronological = _items.reversed.toList();
    final entries = <_PinnedEntry>[];
    DateTime? previousDay;
    for (final message in chronological) {
      final date = DateTime.fromMillisecondsSinceEpoch(message.date * 1000);
      final day = DateTime(date.year, date.month, date.day);
      if (previousDay == null || day != previousDay) {
        entries.add(_PinnedDateEntry(date));
      }
      entries.add(_PinnedMessageEntry(message));
      previousDay = day;
    }
    return entries.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          _header(),
          Expanded(child: _body()),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    final title = _loading || _items.isEmpty
        ? AppStrings.t(AppStringKeys.chatInfoPinnedHighlights)
        : AppStrings.plural(
            AppStringKeys.pinnedMessagesCountTitle,
            _items.length,
          );
    return Container(
      padding: headerChromePaddingOf(context),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: AppIcon(
                    HeroAppIcons.chevronLeft,
                    size: 22,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          AppStrings.t(AppStringKeys.pinnedMessagesEmpty),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    final entries = _entries();
    return ListView.builder(
      reverse: true,
      padding: EdgeInsets.fromLTRB(
        10,
        8,
        10,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return switch (entry) {
          _PinnedDateEntry(:final date) => TimeSeparator(
            unix: date.millisecondsSinceEpoch ~/ 1000,
          ),
          _PinnedMessageEntry(:final message) => _bubble(message),
        };
      },
    );
  }

  Widget _bubble(ChatMessage message) {
    final theme = context.watch<ThemeController>();
    // The whole row jumps to the message, like `onMessageClick` in MODE_PINNED;
    // the absorbed bubble keeps its own tap and buttons from stealing the
    // contact (a pinned list is a jump target, not a second chat).
    return GestureDetector(
      key: ValueKey('pinnedMessage-${message.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _jumpTo(message),
      child: AbsorbPointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: MessageBubble(
            message: message,
            peerTitle: widget.title,
            peerPhoto: _chatPhoto,
            isGroup: _isGroup,
            meName: _meName,
            mePhoto: _mePhoto,
            meId: _meId,
            showAvatarOnlineStatus: theme.showAvatarOnlineStatus,
            forceShowTimestamp: true,
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final c = context.colors;
    final label = _canPin
        ? AppStringKeys.pinnedMessagesUnpinAll
        : AppStringKeys.pinnedMessagesHide;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: GestureDetector(
        key: const ValueKey('pinnedMessagesBottomAction'),
        behavior: HitTestBehavior.opaque,
        onTap: _unpinning ? null : (_canPin ? _unpinAll : _hideBar),
        child: SizedBox(
          height: 48,
          child: Center(
            child: _unpinning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : Text(
                    AppStrings.t(label),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brand,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
