//
//  startup_diagnostics_view.dart
//
//  TEMPORARY (icon-switch cold-start investigation): shows the device-side
//  startup trace and the last uncaught exception as copyable text, because the
//  phone under test has no adb. Reached from Settings > Developer.
//
//  Remove with StartupDiagnostics / StartupTrace once the crash is understood.
//

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app/startup_trace.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class StartupDiagnosticsView extends StatefulWidget {
  const StartupDiagnosticsView({super.key});

  @override
  State<StartupDiagnosticsView> createState() => _StartupDiagnosticsViewState();
}

class _StartupDiagnosticsViewState extends State<StartupDiagnosticsView> {
  Map<String, String> _trace = const <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final trace = await StartupTrace.read();
    if (!mounted) return;
    setState(() {
      _trace = trace;
      _loading = false;
    });
  }

  String get _report {
    final startup = (_trace['startup'] ?? '').trim();
    final crash = (_trace['crash'] ?? '').trim();
    return 'pid=${_trace['pid'] ?? '?'}\n'
        '--- startup trace ---\n'
        '${startup.isEmpty ? AppStrings.t(AppStringKeys.mithkaxStartupDiagnosticsEmpty) : startup}\n'
        '--- last crash ---\n'
        '${crash.isEmpty ? AppStrings.t(AppStringKeys.mithkaxStartupDiagnosticsEmpty) : crash}\n';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _report));
  }

  Future<void> _clear() async {
    await StartupTrace.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.mithkaxStartupDiagnosticsTitle),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            rows: [
              SettingsRow(
                title: AppStrings.t(
                  AppStringKeys.mithkaxStartupDiagnosticsCopy,
                ),
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.documentDuplicate,
                ),
                showChevron: false,
                onTap: _copy,
              ),
              SettingsRow(
                title: AppStrings.t(
                  AppStringKeys.mithkaxStartupDiagnosticsClear,
                ),
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.trash),
                showChevron: false,
                onTap: _clear,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsNote(
            text: AppStrings.t(
              AppStringKeys.mithkaxStartupDiagnosticsDescription,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: c.groupedBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: SelectableText(
                _report,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
