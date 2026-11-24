import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/brand_mark.dart';
import 'package:mithka/components/vip_badge.dart';

void main() {
  testWidgets('the VIP badge is a small labelled mark, not a text pill', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: VipBadge()),
      ),
    );

    expect(tester.getSize(find.byType(VipBadge)), const Size.square(18));
    expect(
      find.descendant(of: find.byType(VipBadge), matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(VipBadge),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('VIP'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the badge fills the mark with Premium gold', (tester) async {
    const key = ValueKey('vip-badge-paint');
    // A white plate behind the badge makes the gold measurable while keeping
    // the glyph's own edges (the interesting part) visible.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Color(0xFFFFFFFF),
              child: VipBadge(size: 48),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final pixels = (await image.toByteData())!.buffer.asUint8List();
      final width = image.width;
      final height = image.height;
      var gold = 0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final offset = (y * width + x) * 4;
          final red = pixels[offset];
          final green = pixels[offset + 1];
          final blue = pixels[offset + 2];
          if (pixels[offset + 3] == 0) continue;
          if (red > 150 && red > blue + 60 && green > blue) gold++;
        }
      }
      // The top-left corner is inside the grid but outside the glyph.
      final corner = pixels[(2 * width + 2) * 4];
      image.dispose();

      // The glyph covers roughly half of the square; a glyph that failed to
      // build (empty path) leaves only the plate behind.
      final share = gold / (width * height);
      expect(share, greaterThan(0.3), reason: 'gold ink share $share');
      expect(share, lessThan(0.8), reason: 'gold ink share $share');
      expect(corner, 255, reason: 'corner must stay background');
    });
  });

  test('the vector glyph matches the shipped raster proportions', () {
    // 24 grid: the mark is taller than wide, fills the height and sits
    // centred. A stale copy of the path (an older mark) would drift here.
    // Path.getBounds() reports control points, so measure the curve itself.
    final samples = <Offset>[];
    for (final metric in brandMarkGlyph.computeMetrics()) {
      for (var offset = 0.0; offset <= metric.length; offset += 0.1) {
        samples.add(metric.getTangentForOffset(offset)!.position);
      }
    }
    final xs = samples.map((point) => point.dx);
    final ys = samples.map((point) => point.dy);
    final left = xs.reduce((a, b) => a < b ? a : b);
    final right = xs.reduce((a, b) => a > b ? a : b);
    final top = ys.reduce((a, b) => a < b ? a : b);
    final bottom = ys.reduce((a, b) => a > b ? a : b);

    expect(bottom - top, closeTo(24, 0.02));
    expect(right - left, closeTo(23, 0.05));
    expect((left + right) / 2, closeTo(12, 0.02));
    expect(top, closeTo(0, 0.02));
    expect(brandMarkGlyph.contains(const Offset(12, 12)), isTrue);
  });
}
