//
//  about_view.dart
//
//  关于 — app identity (penguin mark, name, version) plus tappable links
//  that resolve through the shared link handler.
//

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../app/app_version.dart';
import '../app/telemetry_config.dart';
import '../chat/links_search/link_handler.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import '../update/update_checker.dart';
import 'developer_mode_controller.dart';
import 'feedback_report_view.dart';
import 'startup_diagnostics_view.dart';

class AboutView extends StatefulWidget {
  const AboutView({super.key, this.showBackButton = true});

  final bool showBackButton;

  @override
  State<AboutView> createState() => _AboutViewState();
}

class _AboutViewState extends State<AboutView> {
  static const _channelUrl = 'https://t.me/MithkaX';
  static const _githubUrl = 'https://github.com/TiaraBasori/MithkaX';
  late final Future<AppVersion> _versionFuture = AppVersion.load();
  int _versionTapCount = 0;
  DateTime? _lastVersionTapAt;
  bool _checking = false;
  UpdateCheckOutcome? _updateOutcome;

  /// Trailing text on the update row: the last outcome, or nothing yet.
  String _updateStatusLabel() {
    if (_checking) return AppStrings.t(AppStringKeys.aboutCheckingForUpdates);
    return switch (_updateOutcome) {
      null => '',
      UpdateCheckOutcome.upToDate => AppStrings.t(AppStringKeys.aboutUpToDate),
      UpdateCheckOutcome.unavailable => AppStrings.t(
        AppStringKeys.aboutUpdateCheckFailed,
      ),
      // checkNow already offered the download; the row just records it.
      UpdateCheckOutcome.updateAvailable => AppStrings.t(
        AppStringKeys.aboutDownloadUpdate,
      ),
    };
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _updateOutcome = null;
    });
    final outcome = await UpdateChecker.checkNow(context);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateOutcome = outcome;
    });
  }

  Future<void> _handleVersionTap() async {
    final now = DateTime.now();
    final previous = _lastVersionTapAt;
    _lastVersionTapAt = now;
    if (previous == null ||
        now.difference(previous) > const Duration(seconds: 3)) {
      _versionTapCount = 0;
    }
    _versionTapCount += 1;
    if (_versionTapCount < 20) return;
    _versionTapCount = 0;
    final developer = context.read<DeveloperModeController>();
    if (developer.unlocked) return;
    await developer.unlock();
    if (!mounted) return;
    showToast(context, AppStringKeys.developerModeUnlocked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.aboutTitle),
      showBackButton: widget.showBackButton,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          Center(
            child: Column(
              children: [
                // No tile behind the penguin: the mark is the identity, drawn
                // large on its own instead of framed in a rounded box. The
                // asset is the artwork with its transparent canvas cropped
                // away, so the name sits a token's gap below the ink rather
                // than below the canvas' empty margin.
                const Image(
                  image: ResizeImage(
                    AssetImage('assets/penguin_mark.png'),
                    width: 300,
                  ),
                  height: 84,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Mithka X',
                  style: TextStyle(
                    fontSize: AppTextSize.display,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_handleVersionTap()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: FutureBuilder<AppVersion>(
                      future: _versionFuture,
                      builder: (context, snapshot) {
                        final version = snapshot.data?.display ?? '...';
                        return Text(
                          AppStrings.t(AppStringKeys.aboutVersion, {
                            'value1': version,
                          }),
                          style: TextStyle(
                            fontSize: AppTextSize.footnote,
                            color: c.textSecondary,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          SettingsCard.rows(
            rows: [
              // TEMPORARY: device-side startup trace reader for the
              // icon-switch cold-start crash (no adb on the test phone).
              // Remove with StartupDiagnosticsView.
              SettingsRow(
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.documentDuplicate,
                ),
                title: AppStrings.t(
                  AppStringKeys.mithkaxStartupDiagnosticsTitle,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const StartupDiagnosticsView(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsCard.rows(
            rows: [
              if (UpdateChecker.supportsManualCheck) ...[
                SettingsRow(
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.download,
                  ),
                  title: AppStrings.t(AppStringKeys.aboutCheckForUpdates),
                  value: _updateStatusLabel(),
                  onTap: _checking ? null : () => unawaited(_checkForUpdates()),
                ),
              ],
              if (sentryEnabled) ...[
                SettingsRow(
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.comments,
                  ),
                  title: AppStrings.t(AppStringKeys.aboutReportProblem),
                  value: AppStrings.t(AppStringKeys.aboutReportProblemDetail),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      settings: const RouteSettings(name: '/settings/feedback'),
                      builder: (_) => const FeedbackReportView(),
                    ),
                  ),
                ),
              ],
              SettingsRow(
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.solidPaperPlane,
                ),
                title: AppStrings.t(AppStringKeys.aboutTelegramChannel),
                value: 't.me/MithkaX',
                onTap: () => openLink(context, _channelUrl),
              ),
              SettingsRow(
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.code),
                title: 'GitHub',
                value: 'github.com/TiaraBasori/MithkaX',
                onTap: () => openLink(context, _githubUrl),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
