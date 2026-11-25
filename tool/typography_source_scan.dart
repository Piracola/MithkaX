//
//  typography_source_scan.dart
//
//  Reads every `TextStyle`/`copyWith` call in lib/ and reports the size, line
//  height, and weight each one states. Shared by the CLI report
//  (tool/typography_audit.dart) and the budget gate
//  (test/typography_budget_test.dart) so the number a human reads and the
//  number CI enforces can never disagree.
//

import 'dart:io';

const typographySourceRoot = 'lib';
const typographyLadderSource = 'lib/theme/app_theme.dart';

final _ladderClassRe = RegExp(r'abstract final class AppTextSize \{');
final _ladderConstRe = RegExp(
  r'static const double ([a-zA-Z]+) = ([0-9]+(?:\.[0-9]+)?);',
);

final _fontSizeRe = RegExp(r'fontSize:\s*([0-9]+(?:\.[0-9]+)?)');

/// `height: 20 / 16` states a leading as a ratio; `height: 18` states it
/// outright. Both are line heights, but only the ratio's quotient is one, so
/// the ratio form is matched first.
final _heightRatioRe = RegExp(
  r'height:\s*([0-9]+(?:\.[0-9]+)?)\s*/\s*([0-9]+(?:\.[0-9]+)?)(?![0-9.])',
);
final _heightRe = RegExp(r'height:\s*([0-9]+(?:\.[0-9]+)?)(?![0-9.])');
final _weightRe = RegExp(r'fontWeight:\s*FontWeight\.(w[0-9]{3})');
final _blockRe = RegExp(r'\b(TextStyle|copyWith)\(');

/// One `TextStyle(...)` or `copyWith(...)` that states at least one text
/// property. A style that only sets a colour is not a typography decision and
/// is skipped.
class TextStyleSite {
  const TextStyleSite({
    required this.file,
    required this.line,
    required this.flavor,
    this.size,
    this.height,
    this.weight,
  });

  final String file;
  final int line;

  /// `TextStyle` for a constructed style, `copyWith` for a derived one.
  final String flavor;
  final double? size;
  final double? height;
  final String? weight;

  /// `lib/settings/appearance_view.dart` -> `settings`.
  String get area {
    final parts = file.split('/');
    return parts.length > 2 ? parts[1] : '(root)';
  }
}

/// The `AppTextSize` steps, ascending, mapped to their token names.
///
/// Read out of the token class rather than restated here: the spec lives in one
/// file, so neither the report nor the gate can drift from the code.
Map<double, String> readLadder([String path = typographyLadderSource]) {
  final file = File(path);
  if (!file.existsSync()) return const {};
  final source = file.readAsStringSync();
  final classStart = _ladderClassRe.firstMatch(source);
  if (classStart == null) return const {};
  final bodyEnd = source.indexOf('\n}', classStart.end);
  final body = source.substring(
    classStart.end,
    bodyEnd < 0 ? source.length : bodyEnd,
  );

  final steps = <double, String>{};
  for (final match in _ladderConstRe.allMatches(body)) {
    steps.putIfAbsent(double.parse(match.group(2)!), () => match.group(1)!);
  }
  return {for (final step in steps.keys.toList()..sort()) step: steps[step]!};
}

/// Every typography site in [root], sorted by file and line.
List<TextStyleSite> scanTypographySites([String root = typographySourceRoot]) {
  final files =
      Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  return [
    for (final file in files)
      ...scanTypographySource(
        file.path.replaceAll(r'\', '/'),
        file.readAsStringSync(),
      ),
  ];
}

/// The sites inside one file's [source]. Exposed so the scanner can be
/// exercised on a fixture without touching the tree.
List<TextStyleSite> scanTypographySource(String path, String source) {
  final lineStarts = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }

  int lineOf(int offset) {
    var low = 0;
    var high = lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low + 1;
  }

  final sites = <TextStyleSite>[];
  for (final match in _blockRe.allMatches(source)) {
    final body = _balanced(source, match.end - 1);
    if (body == null) continue;
    final code = _stripComments(body);
    final size = _fontSizeRe.firstMatch(code);
    final height = _readHeight(code);
    final weight = _weightRe.firstMatch(code);
    if (size == null && height == null && weight == null) continue;
    sites.add(
      TextStyleSite(
        file: path,
        line: lineOf(match.start),
        flavor: match.group(1)!,
        size: size == null ? null : double.parse(size.group(1)!),
        height: height,
        weight: weight?.group(1),
      ),
    );
  }
  return sites;
}

/// The leading a style block states, if any.
///
/// A ratio (`20 / 16`) has to be divided before it is a multiplier, and a
/// stated value outside the plausible range is a widget dimension that landed
/// in the arguments rather than a line height.
double? _readHeight(String code) {
  final ratio = _heightRatioRe.firstMatch(code);
  if (ratio != null) {
    final numerator = double.parse(ratio.group(1)!);
    final denominator = double.parse(ratio.group(2)!);
    if (denominator == 0) return null;
    final value = numerator / denominator;
    return _isPlausibleLeading(value) ? _roundLeading(value) : null;
  }
  final plain = _heightRe.firstMatch(code);
  if (plain == null) return null;
  final value = double.parse(plain.group(1)!);
  return _isPlausibleLeading(value) ? value : null;
}

/// `20 / 16` is authored as a ratio, not as `1.25`, so the quotient is rounded
/// before it is counted or grouped.
double _roundLeading(double value) => (value * 1000).roundToDouble() / 1000;

bool _isPlausibleLeading(double value) => value >= 0.8 && value <= 2.5;

/// Drops `//` and `/* */` comments so a stray apostrophe or a commented-out
/// property cannot move a block's contents or its match boundaries.
String _stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final unit = source.codeUnitAt(i);
    if (unit == 0x2F && i + 1 < source.length) {
      final next = source.codeUnitAt(i + 1);
      if (next == 0x2F) {
        while (i < source.length && source.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (next == 0x2A) {
        i += 2;
        while (i + 1 < source.length) {
          if (source.codeUnitAt(i) == 0x2A &&
              source.codeUnitAt(i + 1) == 0x2F) {
            i += 2;
            break;
          }
          i++;
        }
        continue;
      }
    }
    out.writeCharCode(unit);
    i++;
  }
  return out.toString();
}

/// The text between the parenthesis at [open] and its match, skipping any
/// parenthesis inside a string literal or a comment.
String? _balanced(String source, int open) {
  var depth = 0;
  var quote = 0;
  for (var i = open; i < source.length; i++) {
    final unit = source.codeUnitAt(i);
    if (quote != 0) {
      if (unit == 0x5C) {
        i++;
        continue;
      }
      if (unit == quote) quote = 0;
      continue;
    }
    if (unit == 0x2F && i + 1 < source.length) {
      final next = source.codeUnitAt(i + 1);
      if (next == 0x2F) {
        while (i < source.length && source.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (next == 0x2A) {
        i += 2;
        while (i + 1 < source.length) {
          if (source.codeUnitAt(i) == 0x2A &&
              source.codeUnitAt(i + 1) == 0x2F) {
            i += 2;
            break;
          }
          i++;
        }
        i--;
        continue;
      }
    }
    if (unit == 0x27 || unit == 0x22) {
      quote = unit;
      continue;
    }
    if (unit == 0x28) {
      depth++;
    } else if (unit == 0x29) {
      depth--;
      if (depth == 0) return source.substring(open + 1, i);
    }
  }
  return null;
}

/// `10.0` -> `10`, `12.5` -> `12.5`. Used for every key and report cell so a
/// size has exactly one spelling.
String formatSize(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// Places [k] steps on an observed size distribution so the total movement a
/// migration costs is minimal: weighted one-dimensional k-medians.
///
/// The ladder is a design decision, but how much it moves the tree is not. This
/// prices a candidate against the code that exists, so a new step has to earn
/// its place instead of being added because one screen wanted it.
List<double> suggestLadder(Map<double, int> counts, int k) {
  final values = counts.keys.toList()..sort();
  final n = values.length;
  if (n == 0 || k <= 0) return const [];
  if (k >= n) return values;

  final weights = [for (final value in values) counts[value]!];
  final cost = List.generate(n, (_) => List<double>.filled(n, 0));
  for (var i = 0; i < n; i++) {
    for (var j = i; j < n; j++) {
      final median = _weightedMedian(values, weights, i, j);
      var total = 0.0;
      for (var t = i; t <= j; t++) {
        total += weights[t] * (values[t] - median).abs();
      }
      cost[i][j] = total;
    }
  }

  final dp = List.generate(
    k + 1,
    (_) => List<double>.filled(n, double.infinity),
  );
  final cut = List.generate(k + 1, (_) => List<int>.filled(n, -1));
  for (var j = 0; j < n; j++) {
    dp[1][j] = cost[0][j];
  }
  for (var step = 2; step <= k; step++) {
    for (var j = step - 1; j < n; j++) {
      for (var i = step - 1; i <= j; i++) {
        final candidate = dp[step - 1][i - 1] + cost[i][j];
        if (candidate < dp[step][j]) {
          dp[step][j] = candidate;
          cut[step][j] = i;
        }
      }
    }
  }

  final steps = <double>[];
  var end = n - 1;
  for (var step = k; step >= 1; step--) {
    final start = step == 1 ? 0 : cut[step][end];
    steps.insert(
      0,
      _weightedMedian(values, weights, start, end).roundToDouble(),
    );
    end = start - 1;
  }
  return steps.toSet().toList()..sort();
}

double _weightedMedian(
  List<double> values,
  List<int> weights,
  int from,
  int to,
) {
  var total = 0;
  for (var t = from; t <= to; t++) {
    total += weights[t];
  }
  var running = 0;
  for (var t = from; t <= to; t++) {
    running += weights[t];
    if (running * 2 >= total) return values[t];
  }
  return values[to];
}

/// What a candidate ladder would cost: how many sized sites change value, and
/// by how much in total.
({int moved, double distance}) ladderCost(
  Map<double, int> counts,
  List<double> ladder,
) {
  var moved = 0;
  var distance = 0.0;
  for (final entry in counts.entries) {
    final target = _nearestStep(entry.key, ladder);
    if (target == entry.key) continue;
    moved += entry.value;
    distance += (target - entry.key).abs() * entry.value;
  }
  return (moved: moved, distance: distance);
}

double _nearestStep(double value, List<double> ladder) {
  var best = ladder.first;
  var bestDelta = (best - value).abs();
  for (final step in ladder.skip(1)) {
    final delta = (step - value).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = step;
    }
  }
  return best;
}
