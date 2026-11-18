//
//  topic_picker_view.dart
//
//  The middle topic-selection page a forum group lands on when it is opened
//  from the chat list — the page exteraless shows as its TopicsFragment: the
//  group's topics as chat-list-style rows, a "All chats" row that folds the
//  topics back into the ordinary transcript, and the same row actions the
//  conversation rail offers. Nothing here is scoped to a topic yet: picking a
//  row replaces this route with that topic's transcript.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_navigator.dart';
import '../chat/chat_view.dart';
import '../chat/chat_view_model.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'topic_list_actions.dart';
import 'topic_list_row.dart';
import 'topic_navigation.dart';

/// The topic-selection page for [chat] (a forum supergroup). Tapping a topic
/// replaces this page with that topic's [ChatView] transcript; the "All chats"
/// row opens the whole chat the way a non-topic group opens.
class TopicPickerView extends StatefulWidget {
  const TopicPickerView({
    super.key,
    required this.chat,
    this.showBackButton = true,
    this.onOpenTopic,
    this.onBack,
  });

  final ChatSummary chat;

  /// Hides the header's back chevron inside shells that own the back stack.
  final bool showBackButton;

  /// Replaces this page with a topic transcript in an owning shell (split
  /// detail pane); null uses the route stack.
  final void Function(int? topicId)? onOpenTopic;

  final VoidCallback? onBack;

  @override
  State<TopicPickerView> createState() => _TopicPickerViewState();
}

class _TopicPickerViewState extends State<TopicPickerView> {
  late final ChatViewModel _vm;

  @override
  void initState() {
    super.initState();
    // A picker needs only the topic list; the transcript machinery of onAppear
    // (openChat, read marking, history windows) belongs to the page it opens.
    _vm = ChatViewModel(
      chatId: widget.chat.id,
      title: widget.chat.title,
      markReadOnOpen: false,
      seedMessage: widget.chat.lastChatMessage,
    )..isForum = true;
    _vm.addListener(_onModel);
    unawaited(_vm.loadHeaderAndTopics());
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onModel);
    _vm.dispose();
    super.dispose();
  }

  void _openTopic(int? topicId) {
    final onOpenTopic = widget.onOpenTopic;
    if (onOpenTopic != null) {
      onOpenTopic(topicId);
      return;
    }
    unawaited(
      pushAppChatRoute<void>(
        context,
        AppChatPageRoute<void>(
          builder: (_) => ChatView(
            chatId: widget.chat.id,
            title: widget.chat.title,
            forumTopicId: topicId,
          ),
        ),
      ),
    );
  }

  Future<void> _createTopic() async {
    final draft = await showDialog<TopicDraft>(
      context: context,
      builder: (dialogContext) => TopicDraftDialog(
        title: AppStrings.t(AppStringKeys.groupAdministrationNewTopic),
        initialName: '',
        initialColor:
            topicIconColors[_vm.forumTopics.length % topicIconColors.length],
        initialCustomEmojiId: 0,
        canChangeColor: true,
      ),
    );
    if (!mounted || draft == null || draft.name.isEmpty) return;
    try {
      final created = await _vm.createForumTopic(
        name: draft.name,
        iconColor: draft.color,
        iconCustomEmojiId: draft.customEmojiId,
      );
      if (mounted && created != null && created != 0) {
        _openTopic(created);
      }
    } catch (error) {
      _showCreateFailure(error);
    }
  }

  void _showCreateFailure(Object error) {
    if (!mounted) return;
    showToast(
      context,
      AppStrings.t(AppStringKeys.groupAdministrationCouldnTCreateTopicValue1, {
        'value1': error,
      }),
    );
  }

  Future<void> _markAllRead() async {
    try {
      await _vm.markForumTopicsRead(_vm.forumTopics.map((t) => t.id));
    } catch (_) {}
    if (!mounted) return;
    if (_vm.takeBulkReadFailure()) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.topicChatMarkAllReadFailed),
      );
    }
  }

  ForumTopicOption? _topicById(int id) {
    for (final topic in _vm.forumTopics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

  Future<void> _showRowMenu(
    TopicNavigationItem item,
    Offset? globalPosition,
  ) async {
    final topic = _topicById(item.id);
    if (topic == null) return;
    // The creator-deletion carve-out probes the topic's live history; probe
    // before the menu is offered, exactly the way the transcript's menu does.
    if (!topic.isGeneral &&
        _vm.canDeleteForumTopics != true &&
        _vm.creatorOfTopic(topic)) {
      await _vm.ensureTopicCreatorDeletable(topic.id);
      if (!mounted) return;
    }
    final current = _topicById(topic.id);
    if (current == null) return;
    await showTopicRowMenuSheet(
      context: context,
      topic: item,
      actions: topicRowActions(
        topic: item,
        canManage: _vm.canManageTopics,
        canDelete: _vm.canDeleteTopic(current),
        onMarkRead: () => _vm.markForumTopicRead(current),
        onTogglePinned: () =>
            _vm.setForumTopicPinned(current.id, pinned: !current.isPinned),
        onToggleMuted: () =>
            _vm.setForumTopicMuted(current.id, muted: !current.isMuted),
        onEdit: () => _editTopic(current),
        onToggleClosed: () =>
            _vm.setForumTopicClosed(current.id, closed: !current.isClosed),
        onDelete: () => _deleteTopic(current),
      ),
    );
  }

  Future<void> _editTopic(ForumTopicOption topic) async {
    if (topic.isGeneral) return;
    final draft = await showDialog<TopicDraft>(
      context: context,
      builder: (dialogContext) => TopicDraftDialog(
        title: AppStrings.t(AppStringKeys.groupAdministrationEditTopic),
        initialName: topic.name,
        initialColor: topic.iconColor == 0
            ? topicIconColors.first
            : topic.iconColor,
        initialCustomEmojiId: topic.iconCustomEmojiId,
        canChangeColor: false,
      ),
    );
    if (!mounted || draft == null || draft.name.isEmpty) return;
    try {
      await _vm.editForumTopic(
        forumTopicId: topic.id,
        name: draft.name,
        iconCustomEmojiId: draft.customEmojiId,
      );
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.groupAdministrationCouldnTEditTopicValue1, {
          'value1': error,
        }),
      );
    }
  }

  Future<void> _deleteTopic(ForumTopicOption topic) async {
    if (topic.isGeneral || !_vm.canDeleteTopic(topic)) return;
    final ok = await confirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.groupAdministrationDeleteTopicAndMessages,
        {'value1': topic.name},
      ),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    // The dialog can stay open across a rights change; re-verify before the
    // destructive request leaves, exactly the way the transcript's menu does.
    final current = _topicById(topic.id);
    if (current == null || !_vm.canDeleteTopic(current)) return;
    try {
      await _vm.deleteForumTopic(current.id);
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(
          AppStringKeys.groupAdministrationCouldnTDeleteTopicValue1,
          {'value1': error},
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final topics = _vm.forumTopics;
    final loading = _vm.forumTopicsLoading && topics.isEmpty;
    final anyUnread = topics.any((t) => t.unreadCount > 0);
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(
            title: widget.chat.title,
            onBack: widget.showBackButton
                ? widget.onBack ?? () => Navigator.of(context).maybePop()
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (anyUnread)
                  AppInteractiveSurface(
                    semanticLabel: AppStrings.t(
                      AppStringKeys.topicChatMarkAllRead,
                    ),
                    onTap: () => unawaited(_markAllRead()),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: AppIcon(
                        HeroAppIcons.circleCheck,
                        size: AppIconSize.nav,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                if (_vm.canCreateForumTopics)
                  AppInteractiveSurface(
                    semanticLabel: AppStrings.t(
                      AppStringKeys.groupAdministrationNewTopic,
                    ),
                    onTap: () => unawaited(_createTopic()),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: AppIcon(
                        HeroAppIcons.plus,
                        size: AppIconSize.nav,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: AppActivityIndicator())
                : topics.isEmpty
                ? _emptyState(context)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: topics.length + 1,
                    itemBuilder: (context, index) {
                      final topic = index == 0 ? null : topics[index - 1];
                      return TopicListRowView(
                        topic: topic == null ? null : _navItem(topic),
                        selected: false,
                        onTap: () => _openTopic(topic?.id),
                        onLongPress: topic == null
                            ? null
                            : () => _showRowMenu(_navItem(topic), null),
                        onSecondaryTapDown: topic == null
                            ? null
                            : (details) => _showRowMenu(
                                _navItem(topic),
                                details.globalPosition,
                              ),
                        generalAvatarTitle: widget.chat.title,
                        generalAvatarPhoto: widget.chat.photo,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  TopicNavigationItem _navItem(ForumTopicOption topic) => TopicNavigationItem(
    id: topic.id,
    name: topic.name,
    iconCustomEmojiId: topic.iconCustomEmojiId,
    iconColor: topic.iconColor,
    unreadCount: topic.unreadCount,
    isMuted: topic.isMuted,
    isPinned: topic.isPinned,
    isGeneral: topic.isGeneral,
    isClosed: topic.isClosed,
    lastPreview: topic.lastPreview,
    lastSender: topic.lastSender,
    lastMessageDate: topic.lastMessageDate,
  );

  Widget _emptyState(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(HeroAppIcons.hashtag, size: 36, color: c.textTertiary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              _vm.forumTopicsLoading
                  ? AppStrings.t(AppStringKeys.chatLoadingTopics)
                  : AppStrings.t(AppStringKeys.chatNoTopics),
              style: AppTextStyle.body(c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
