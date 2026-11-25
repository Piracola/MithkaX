import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'brand_mark.dart';

/// The app mark in Premium gold, shown next to a Telegram Premium user's name.
class VipBadge extends StatelessWidget {
  const VipBadge({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppStringKeys.vipBadgeLabel.l10n(context),
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: const CustomPaint(painter: _GoldMarkPainter()),
      ),
    );
  }
}

/// Fills [brandMarkGlyph] with the Premium gold gradient.
///
/// Drawn as path geometry rather than the raster mark: at 18 pt the badge sits
/// beside a name in every list, and the glyph's rounded corners stay crisp
/// only when they are vector edges.
class _GoldMarkPainter extends CustomPainter {
  const _GoldMarkPainter();

  static const _gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF2BC2E), Color(0xFFC98204)],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawPath(
      brandMarkGlyph,
      Paint()
        ..isAntiAlias = true
        ..shader = _gradient.createShader(const Rect.fromLTWH(0, 0, 24, 24)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoldMarkPainter oldDelegate) => false;
}
