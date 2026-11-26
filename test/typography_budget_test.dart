//
//  typography_budget_test.dart
//
//  The gate half of the typography loop. It pins two numbers against the
//  tree:
//
//    * how many `TextStyle(...)` sites state a font size off the token ladder;
//    * how many state their own line height instead of inheriting a role's.
//
//  Both are budgets, not passes. A PR may lower them and may never raise them.
//  That is what lets a 1148-site migration finish across many PRs — each one
//  has to make the tree strictly no worse, and the end state is enforced by the
//  same test once the budgets reach zero.
//
//  Regenerate the measurement with `dart run tool/typography_audit.dart`; the
//  report it writes explains every site the budget counts.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/app_theme.dart';

import '../tool/typography_audit.dart';
import '../tool/typography_source_scan.dart';

/// Sized sites that may still sit off the token ladder.
///
/// This reached zero, so the gate is now absolute: a new literal size off the
/// ladder fails here rather than fitting under a budget. The hand-written
/// exceptions (the wordmark, the hidden one-time-code field, the dice glyph)
/// carry a marker and are not counted, so the number that is left is genuinely
/// zero rather than zero-except-the-things-we-agreed-to.
const _offLadderBudget = 0;

/// Sites that may still declare their own line height.
///
/// A role carries its size, weight and leading together. Every hand-written
/// `height:` is a role the tree has not named yet, so this budget tracks the
/// same migration as the one above.
const _heightBudget = 126;

/// Sites that may still state their own font size.
///
/// The two budgets above only reject *wrong* literals, so a site that writes an
/// on-ladder `fontSize: 14` costs nothing there. This one counts what the
/// migration actually removes: a style that picks its size by hand instead of
/// taking a role from `AppTextStyle.<role>()`, and therefore never picks up the
/// role's leading. It is the number that reaches zero when the tree is on
/// roles; the other two reach zero earlier.
const _literalStyleBudget = 977;

void main() {
  late List<TextStyleSite> sites;
  late Map<String, Object?> report;

  setUpAll(() {
    final ladder = readLadder();
    expect(
      ladder,
      isNotEmpty,
      reason: 'AppTextSize declares no ladder; $typographyLadderSource moved?',
    );
    sites = scanTypographySites();
    report = buildReport(sites, ladder);
  });

  test('no TextStyle states a font size off the ladder', () {
    final offenders = sites
        .where((site) => site.size != null)
        .where((site) => !readLadder().containsKey(site.size))
        .toList();
    expect(
      offenders.length,
      lessThanOrEqualTo(_offLadderBudget),
      reason:
          'Typed sites off the ladder: ${offenders.length}, budget '
          '$_offLadderBudget. Fold each into its nearest step; see '
          'build/typography/static-report.md. '
          '${_sample(offenders)}',
    );
  });

  test('no TextStyle states its own line height', () {
    final offenders = sites.where((site) => site.height != null).toList();
    expect(
      offenders.length,
      lessThanOrEqualTo(_heightBudget),
      reason:
          'Sites declaring a line height: ${offenders.length}, budget '
          '$_heightBudget. A role already carries its leading — use '
          'AppTextStyle.<role>() instead of pairing a size with a height. '
          '${_sample(offenders)}',
    );
  });

  test('no TextStyle picks its size by hand', () {
    final offenders = sites.where((site) => site.size != null).toList();
    expect(
      offenders.length,
      lessThanOrEqualTo(_literalStyleBudget),
      reason:
          'TextStyle sites stating a font size: ${offenders.length}, budget '
          '$_literalStyleBudget. A style built from a raw fontSize never picks '
          'up a role leading. Use AppTextStyle.<role>(). '
          '${_sample(offenders)}',
    );
  });

  test('every ladder step names a leading', () {
    expect(
      AppTextLeading.ladderKeys,
      readLadder().keys.toSet(),
      reason:
          'AppTextLeading and AppTextSize must cover exactly the same steps. '
          'A step without a leading would silently inherit body leading.',
    );
  });

  test('the exceptions are the ones DESIGN.md names, and no more', () {
    // The marker turns off the two gates above for one style. Three call sites
    // are allowed to use it: the wordmark, the hidden one-time-code field, and
    // the dice glyph. A fourth is a decision someone has to make in DESIGN.md,
    // not something to slip past the budget.
    final marked = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .expand((file) => file.readAsLinesSync())
        .where((line) => line.contains(typographyExceptionMarker))
        .length;
    expect(
      marked,
      lessThanOrEqualTo(3),
      reason:
          'Declared typography exceptions: $marked, allowed 3. Add the new '
          'exception to DESIGN.md before marking another site.',
    );
  });

  test('the report and the gate count the same tree', () {
    expect(
      report['offLadder'],
      sites
          .where((site) => site.size != null)
          .where((site) => !readLadder().containsKey(site.size))
          .length,
      reason: 'buildReport and this test must not disagree on the count',
    );
    expect(
      report['sitesWithHeight'],
      sites.where((s) => s.height != null).length,
    );
  });
}

String _sample(List<TextStyleSite> offenders) {
  if (offenders.isEmpty) return 'No sites left.';
  final head = offenders.take(5).map((s) => '${s.file}:${s.line}').join(', ');
  final more = offenders.length > 5 ? ' (+${offenders.length - 5} more)' : '';
  return 'First offenders: $head.$more';
}
