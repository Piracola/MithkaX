//
//  typography_metrics.dart
//
//  Rendered-geometry half of the typography loop. The static audit reads what
//  the source *says*; this reads what the framework *lays out* — the resolved
//  size, the line box it actually occupies, and whether it had to be clipped.
//
//  Layout is the part a pixel diff cannot answer on CI: no bundled UI font, no
//  stable raster across platforms, but every metric here comes from the same
//  layout engine on every machine, so a shift means the typography moved and
//  not that the renderer did.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Committed baselines. Reviewable in the PR diff; the probing output they are
/// compared against lands in gitignored build/typography/.
const _baselineDir = 'test/typography';

/// Re-bless the committed baselines. A batch that deliberately changes the
/// hierarchy runs with this set and the baseline diff becomes its evidence.
const updateTypographyBaseline = bool.fromEnvironment(
  'UPDATE_TYPOGRAPHY_BASELINE',
);

/// One laid-out text run, normalised against its own font size so the numbers
/// survive a change of typeface.
@immutable
class TextRun {
  const TextRun({
    required this.text,
    required this.size,
    required this.weight,
    required this.height,
    required this.boxWidth,
    required this.boxHeight,
    required this.clipped,
  });

  final String text;
  final double size;
  final int weight;

  /// The declared line-height multiplier, or null when the style inherits one.
  final double? height;

  /// The run's laid-out box, in font-size units.
  final double boxWidth;
  final double boxHeight;

  /// True when `maxLines` cut the run short.
  final bool clipped;

  /// Identity across code changes: the copy and the size. A run that keeps
  /// both but changes its line box is drift worth explaining.
  String get key => '$text|${_round(size)}';

  Map<String, Object?> toJson() => {
    'text': text,
    'size': size,
    'weight': weight,
    'height': height,
    'boxW': _round(boxWidth / size),
    'boxH': _round(boxHeight / size),
    'clipped': clipped,
  };

  static double _round(double value) => (value * 1000).roundToDouble() / 1000;
}

/// Every text run currently laid out, in a stable order.
List<TextRun> collectTextRuns(WidgetTester tester) {
  final runs = <TextRun>[];
  for (final element in tester.allElements) {
    final object = element.renderObject;
    if (object is! RenderParagraph || !object.hasSize) continue;
    final style = object.text.style;
    final size = style?.fontSize;
    if (size == null || size <= 0) continue;
    runs.add(
      TextRun(
        text: object.text.toPlainText(),
        size: size,
        weight: (style?.fontWeight ?? FontWeight.w400).value,
        height: style?.height,
        boxWidth: object.size.width,
        boxHeight: object.size.height,
        clipped: object.didExceedMaxLines,
      ),
    );
  }
  runs.sort((a, b) => a.key.compareTo(b.key));
  return runs;
}

/// Records the scene, then compares it against the committed baseline.
///
/// With [updateTypographyBaseline] set, the committed baseline itself is
/// rewritten, so re-blessing shows up in the diff and gets reviewed. Without a
/// baseline at all the scene is only recorded, which lets a new probe land in
/// the same PR as the behaviour it measures; the copy it writes under
/// `build/typography/` is the one to commit.
Future<void> expectTypographyBaseline(
  WidgetTester tester,
  String scene,
  List<TextRun> runs,
) async {
  final current = <String, Map<String, Object?>>{};
  final seen = <String, int>{};
  for (final run in runs) {
    final base = run.key;
    final occurrence = seen.update(
      base,
      (count) => count + 1,
      ifAbsent: () => 0,
    );
    current[occurrence == 0 ? base : '$base#$occurrence'] = {
      'k': occurrence == 0 ? base : '$base#$occurrence',
      ...run.toJson(),
    };
  }

  final baseline = File('$_baselineDir/$scene.json');
  final recorded = const JsonEncoder.withIndent(
    '  ',
  ).convert(current.values.toList());

  if (updateTypographyBaseline) {
    baseline.parent.createSync(recursive: true);
    baseline.writeAsStringSync(recorded);
    return;
  }

  if (!baseline.existsSync()) {
    Directory('build/typography').createSync(recursive: true);
    File('build/typography/$scene.json').writeAsStringSync(recorded);
    return;
  }

  final expected = <String, Map<String, Object?>>{
    for (final entry
        in (jsonDecode(baseline.readAsStringSync()) as List)
            .cast<Map<String, Object?>>())
      entry['k']! as String: entry,
  };

  final drift = <String>[];
  for (final entry in current.entries) {
    final before = expected[entry.key];
    if (before == null) {
      drift.add(
        'added    ${entry.value['size']}  "${entry.value['text']}"  '
        'box ${entry.value['boxW']}x${entry.value['boxH']}',
      );
      continue;
    }
    for (final field in const ['weight', 'height', 'boxW', 'boxH', 'clipped']) {
      if (before[field] != entry.value[field]) {
        drift.add(
          'changed  ${entry.value['size']}  "${entry.value['text']}"  '
          '$field ${before[field]} -> ${entry.value[field]}',
        );
      }
    }
  }
  for (final entry in expected.entries) {
    if (!current.containsKey(entry.key)) {
      drift.add('removed  ${entry.value['size']}  "${entry.value['text']}"');
    }
  }

  expect(
    drift,
    isEmpty,
    reason:
        'Rendered typography drifted from $_baselineDir/$scene.json.\n'
        'Re-bless with --dart-define=UPDATE_TYPOGRAPHY_BASELINE=true when the '
        'change is intended, then review the baseline diff:\n'
        '${drift.join('\n')}',
  );
}
