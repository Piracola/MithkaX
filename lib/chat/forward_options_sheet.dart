//
//  forward_options_sheet.dart
//
//  The forward-preview options panel (转发选项), opened by tapping the
//  composer's pending-forward banner. Mirrors the reference client's forward
//  preview menu: hide-sender / remove-caption toggles (independent, with the
//  caption→copy forcing rule), render-markdown, change recipient, apply,
//  cancel.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'forward_handoff.dart';

/// The result of a session with [ForwardOptionsSheet].
sealed class ForwardOptionsResult {
  const ForwardOptionsResult();
}

/// Keep the forward with its current options.
class ForwardOptionsApply extends ForwardOptionsResult {
  const ForwardOptionsApply();
}

/// Drop the pending forward (banner close equivalent).
class ForwardOptionsCancel extends ForwardOptionsResult {
  const ForwardOptionsCancel();
}

/// Pick a different recipient for the forward.
class ForwardOptionsChangeRecipient extends ForwardOptionsResult {
  const ForwardOptionsChangeRecipient();
}

class ForwardOptionsSheet extends StatelessWidget {
  const ForwardOptionsSheet({super.key, required this.forward});

  final PendingForward forward;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      key: const ValueKey('composerForwardOptionsSheet'),
      color: colors.panelBackground,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStringKeys.chatForwardOptionsTitle.l10n(context),
                    style: AppTextStyle.title(
                      colors.textPrimary,
                      weight: AppTextWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _ForwardOptionToggleRow(
              key: const ValueKey('composerForwardOptionSender'),
              icon: HeroAppIcons.user,
              label: AppStringKeys.chatForwardRemoveSender.l10n(context),
              value: forward.removeSender,
              onChanged: forward.toggleSender,
            ),
            if (forward.hasCaption)
              _ForwardOptionToggleRow(
                key: const ValueKey('composerForwardOptionCaption'),
                icon: HeroAppIcons.image,
                label: AppStringKeys.chatForwardRemoveCaption.l10n(context),
                value: forward.removeCaption,
                onChanged: forward.toggleCaption,
              ),
            if (forward.markdownOffer.available)
              _ForwardOptionToggleRow(
                key: const ValueKey('composerForwardOptionMarkdown'),
                icon: HeroAppIcons.code,
                label: AppStringKeys.chatForwardRenderMarkdown.l10n(context),
                value: forward.renderMarkdown,
                onChanged: forward.toggleRenderMarkdown,
              ),
            const SizedBox(height: 6),
            _ForwardOptionMenuRow(
              key: const ValueKey('composerForwardOptionRecipient'),
              icon: HeroAppIcons.forward,
              label: AppStringKeys.chatForwardChangeRecipient.l10n(context),
              onTap: () => Navigator.of(
                context,
              ).pop(const ForwardOptionsChangeRecipient()),
            ),
            const SizedBox(height: 6),
            _ForwardOptionMenuRow(
              key: const ValueKey('composerForwardOptionApply'),
              icon: HeroAppIcons.check,
              label: AppStringKeys.composerReplyOptionApply.l10n(context),
              onTap: () =>
                  Navigator.of(context).pop(const ForwardOptionsApply()),
            ),
            _ForwardOptionMenuRow(
              key: const ValueKey('composerForwardOptionCancel'),
              icon: HeroAppIcons.trash,
              label: AppStringKeys.composerReplyOptionCancel.l10n(context),
              color: AppTheme.tagRed,
              onTap: () =>
                  Navigator.of(context).pop(const ForwardOptionsCancel()),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: Text(
                  AppStringKeys.composerReplyOptionsHint.l10n(context),
                  style: AppTextStyle.body(colors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardOptionToggleRow extends StatelessWidget {
  const _ForwardOptionToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final AppIconData icon;
  final String label;
  final bool value;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _ForwardOptionMenuRow(
      icon: icon,
      label: label,
      trailing: _ForwardToggle(value: value),
      onTap: onChanged,
    );
  }
}

class _ForwardToggle extends StatelessWidget {
  const _ForwardToggle({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: value ? colors.linkBlue : colors.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: value ? colors.linkBlue : colors.divider),
      ),
      child: value
          ? const AppIcon(HeroAppIcons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// One full-width 48dp menu row: icon, label, optional trailing control.
class _ForwardOptionMenuRow extends StatelessWidget {
  const _ForwardOptionMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.color,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              AppIcon(icon, size: 19, color: color ?? colors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyle.bodyLarge(
                    color ?? colors.textPrimary,
                    weight: AppTextWeight.medium,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
