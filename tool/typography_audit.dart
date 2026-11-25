//
//  typography_audit.dart
//
//  Static half of the typography loop: every TextStyle in lib/, classified
//  against the token ladder, with the migration budget each area has left.
//
//      dart run tool/typography_audit.dart
//
//  The report lands in build/typography/, which is gitignored — it is a
//  measurement of the current tree, not a committed artifact. The gate that
//  keeps the numbers moving in one direction is test/typography_budget_test.dart.
//

import 'dart:convert';
import 'dart:io';

import 'typography_source_scan.dart';

const _outputDir = 'build/typography';

void main() {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this from the repository root.');
    exit(2);
  }
  final ladder = readLadder();
  if (ladder.isEmpty) {
    stderr.writeln(
      'No `static const double` steps found in $typographyLadderSource.',
    );
    exit(2);
  }

  final sites = scanTypographySites();
  final report = buildReport(sites, ladder);
  final outDirectory = Directory(_outputDir)..createSync(recursive: true);
  File(
    '${outDirectory.path}/static.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  File(
    '${outDirectory.path}/static-report.md',
  ).writeAsStringSync(renderReport(report, ladder));
  stdout.writeln(
    'on ladder: ${report['onLadder']} / ${report['sizedSites']} '
    '(${_percent(report)})   off ladder: ${report['offLadder']}   '
    'line heights stated: ${report['sitesWithHeight']}\n'
    'report: ${outDirectory.path}/static-report.md',
  );
}

String _percent(Map<String, Object?> report) {
  final sized = report['sizedSites']! as int;
  if (sized == 0) return '0%';
  return '${((report['onLadder']! as int) * 100 / sized).round()}%';
}

/// The whole measurement, as data. Split from rendering so a test can assert
/// on the numbers the report shows.
Map<String, Object?> buildReport(
  List<TextStyleSite> sites,
  Map<double, String> ladder,
) {
  final sized = sites.where((site) => site.size != null).toList();
  final onLadder = sized.where((site) => ladder.containsKey(site.size)).length;

  final sizeCounts = <double, int>{};
  for (final site in sized) {
    sizeCounts.update(site.size!, (count) => count + 1, ifAbsent: () => 1);
  }
  final sizes = sizeCounts.keys.toList()..sort();

  final heights = <double, int>{};
  for (final site in sites.where((site) => site.height != null)) {
    heights.update(site.height!, (count) => count + 1, ifAbsent: () => 1);
  }

  final weights = <String, int>{};
  for (final site in sites.where((site) => site.weight != null)) {
    weights.update(site.weight!, (count) => count + 1, ifAbsent: () => 1);
  }

  final areas = <String, ({int total, int offLadder})>{};
  for (final site in sized) {
    final current = areas[site.area] ?? (total: 0, offLadder: 0);
    areas[site.area] = (
      total: current.total + 1,
      offLadder: current.offLadder + (ladder.containsKey(site.size) ? 0 : 1),
    );
  }
  final orderedAreas = areas.keys.toList()
    ..sort((a, b) => areas[b]!.offLadder.compareTo(areas[a]!.offLadder));

  return {
    'ladder': ladder.keys.toList(),
    'scannedFiles': <String>{for (final site in sites) site.file}.length,
    'textStyleSites': sites.length,
    'sizedSites': sized.length,
    'onLadder': onLadder,
    'offLadder': sized.length - onLadder,
    'sitesWithHeight': sites.where((site) => site.height != null).length,
    'literalSites': sites.length,
    'proposals': [
      for (final k in const [8, 10, 12]) _proposal(sizeCounts, k),
    ],
    'sizes': [
      for (final size in sizes) {'size': size, 'count': sizeCounts[size]},
    ],
    'offLadderSizes': [
      for (final size in sizes.where((size) => !ladder.containsKey(size)))
        {
          'size': size,
          'count': sizeCounts[size],
          'nearest': _nearest(size, ladder),
          'sites': [
            for (final site in sized.where((site) => site.size == size))
              '${site.file}:${site.line}',
          ],
        },
    ],
    'heights': [
      for (final height
          in heights.keys.toList()
            ..sort((a, b) => heights[b]!.compareTo(heights[a]!)))
        {'height': height, 'count': heights[height]},
    ],
    'weights': weights,
    'areas': [
      for (final area in orderedAreas)
        {
          'area': area,
          'total': areas[area]!.total,
          'offLadder': areas[area]!.offLadder,
        },
    ],
  };
}

Map<String, Object?> _proposal(Map<double, int> counts, int steps) {
  final ladder = suggestLadder(counts, steps);
  final cost = ladderCost(counts, ladder);
  return {
    'steps': steps,
    'ladder': ladder,
    'moved': cost.moved,
    'distance': cost.distance,
  };
}

double _nearest(double value, Map<double, String> ladder) {
  var best = ladder.keys.first;
  var bestDelta = (best - value).abs();
  for (final step in ladder.keys.skip(1)) {
    final delta = (step - value).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = step;
    }
  }
  return best;
}

String renderReport(Map<String, Object?> report, Map<double, String> ladder) {
  final buffer = StringBuffer()
    ..writeln('# Typography audit')
    ..writeln()
    ..writeln(
      'Ladder read from $typographyLadderSource: '
      '${ladder.keys.map(formatSize).join(' / ')}. '
      'Off-ladder literals fold into the nearest step.',
    )
    ..writeln()
    ..writeln('| metric | value |')
    ..writeln('|---|---|')
    ..writeln('| scanned files | ${report['scannedFiles']} |')
    ..writeln('| TextStyle sites | ${report['textStyleSites']} |')
    ..writeln('| sites stating a size | ${report['sizedSites']} |')
    ..writeln('| on the ladder | ${report['onLadder']} |')
    ..writeln('| off the ladder | ${report['offLadder']} |')
    ..writeln('| sites stating a line height | ${report['sitesWithHeight']} |')
    ..writeln();

  buffer
    ..writeln('## Off-ladder sizes')
    ..writeln()
    ..writeln('| size | count | folds into | first site |')
    ..writeln('|---|---|---|---|');
  for (final entry in (report['offLadderSizes']! as List).cast<Map>()) {
    final sites = (entry['sites'] as List).cast<String>();
    buffer.writeln(
      '| ${formatSize(entry['size'] as double)} | ${entry['count']} | '
      '${formatSize(entry['nearest'] as double)} | ${sites.first}'
      '${sites.length > 1 ? ' (+${sites.length - 1})' : ''} |',
    );
  }
  buffer.writeln();

  buffer
    ..writeln('## Size histogram')
    ..writeln()
    ..writeln('| size | token | count |')
    ..writeln('|---|---|---|');
  for (final entry in (report['sizes']! as List).cast<Map>()) {
    final size = entry['size'] as double;
    buffer.writeln(
      '| ${formatSize(size)} | ${ladder[size] ?? '—'} | ${entry['count']} |',
    );
  }
  buffer.writeln();

  buffer
    ..writeln('## Stated line heights')
    ..writeln()
    ..writeln('| height | count |')
    ..writeln('|---|---|');
  for (final entry in (report['heights']! as List).cast<Map>()) {
    buffer.writeln(
      '| ${formatSize(entry['height'] as double)} | ${entry['count']} |',
    );
  }
  buffer.writeln();

  buffer
    ..writeln('## Candidate ladders')
    ..writeln()
    ..writeln(
      'Weighted k-medians over the sizes actually in the tree: the ladder that '
      'moves the fewest sites for a given number of steps. `moved` counts sized '
      'sites whose value changes; `distance` sums the points of movement. '
      'A candidate that cannot beat the current ladder is not worth adopting.',
    )
    ..writeln()
    ..writeln('| steps | ladder | moved | distance |')
    ..writeln('|---|---|---|---|');
  for (final entry in (report['proposals']! as List).cast<Map>()) {
    buffer.writeln(
      '| ${entry['steps']} | '
      '${(entry['ladder'] as List).map((step) => formatSize(step as double)).join(' / ')} '
      '| ${entry['moved']} | ${(entry['distance'] as double).toStringAsFixed(0)} |',
    );
  }
  buffer.writeln();

  buffer
    ..writeln('## Migration budget by area')
    ..writeln()
    ..writeln(
      '`off the ladder` is what this area must drive to zero; `total` is how '
      'much of it a full token migration still has to cover.',
    )
    ..writeln()
    ..writeln('| area | total | off the ladder |')
    ..writeln('|---|---|---|');
  for (final entry in (report['areas']! as List).cast<Map>()) {
    buffer.writeln(
      '| lib/${entry['area']} | ${entry['total']} | ${entry['offLadder']} |',
    );
  }
  return buffer.toString();
}
