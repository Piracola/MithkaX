import 'package:flutter/widgets.dart';

/// The app mark: one flat glyph on transparency.
///
/// The artwork carries a single colour, so every surface tints it to its own
/// ink instead of shipping a copy per theme: pass the ink to `Image.color`
/// (its blend mode is [BlendMode.srcIn], so only the mark's alpha survives).
/// The theme's primary text colour already follows the light/dark appearance,
/// and the splash passes white because it sits on the brand gradient.
const String brandMarkAsset = 'assets/brand_mark.png';

/// The same glyph with its transparent canvas trimmed away, for layouts that
/// space the mark by its ink rather than by a square box.
const String brandMarkInkAsset = 'assets/brand_mark_ink.png';

/// The mark as vector geometry on a 24 × 24 grid, vertically filling it.
///
/// The raster asset covers every ordinary surface; this copy exists for
/// painters that fill the glyph themselves (the gold VIP badge) and must stay
/// crisp at 18 pt.
final Path brandMarkGlyph = Path()
  ..moveTo(0.5, 9.354)
  ..cubicTo(0.5, 8.933, 0.5, 8.512, 0.67, 8.071)
  ..cubicTo(0.753, 7.855, 0.87, 7.652, 1.016, 7.472)
  ..cubicTo(1.313, 7.105, 1.678, 6.894, 2.043, 6.683)
  ..lineTo(12.394, 0.707)
  ..cubicTo(13.111, 0.293, 13.828, -0.121, 14.55, 0.033)
  ..cubicTo(14.854, 0.098, 15.131, 0.257, 15.339, 0.489)
  ..cubicTo(15.833, 1.037, 15.833, 1.865, 15.833, 2.692)
  ..lineTo(15.833, 5.191)
  ..cubicTo(15.833, 5.688, 15.833, 6.184, 16.13, 6.513)
  ..cubicTo(16.255, 6.652, 16.42, 6.748, 16.603, 6.787)
  ..cubicTo(17.036, 6.879, 17.466, 6.631, 17.896, 6.382)
  ..lineTo(20.061, 5.133)
  ..cubicTo(20.778, 4.719, 21.494, 4.305, 22.216, 4.459)
  ..cubicTo(22.521, 4.524, 22.797, 4.683, 23.006, 4.915)
  ..cubicTo(23.5, 5.463, 23.5, 6.291, 23.5, 7.119)
  ..lineTo(23.5, 19.072)
  ..cubicTo(23.5, 19.493, 23.5, 19.914, 23.33, 20.355)
  ..cubicTo(23.247, 20.572, 23.13, 20.774, 22.984, 20.955)
  ..cubicTo(22.687, 21.322, 22.322, 21.532, 21.957, 21.743)
  ..lineTo(19.272, 23.293)
  ..cubicTo(18.555, 23.707, 17.839, 24.121, 17.117, 23.967)
  ..cubicTo(16.812, 23.903, 16.535, 23.743, 16.327, 23.511)
  ..cubicTo(15.833, 22.963, 15.833, 22.135, 15.833, 21.308)
  ..lineTo(15.833, 18.809)
  ..cubicTo(15.833, 18.312, 15.833, 17.816, 15.537, 17.487)
  ..cubicTo(15.412, 17.348, 15.246, 17.252, 15.063, 17.213)
  ..cubicTo(14.63, 17.121, 14.2, 17.369, 13.77, 17.618)
  ..lineTo(11.606, 18.867)
  ..cubicTo(10.889, 19.281, 10.172, 19.695, 9.45, 19.541)
  ..cubicTo(9.146, 19.476, 8.869, 19.317, 8.661, 19.085)
  ..cubicTo(8.167, 18.537, 8.167, 17.709, 8.167, 16.881)
  ..lineTo(8.167, 14.382)
  ..cubicTo(8.167, 13.886, 8.167, 13.389, 7.87, 13.06)
  ..cubicTo(7.745, 12.922, 7.58, 12.826, 7.397, 12.787)
  ..cubicTo(6.964, 12.695, 6.534, 12.943, 6.104, 13.191)
  ..lineTo(3.939, 14.441)
  ..cubicTo(3.222, 14.855, 2.506, 15.268, 1.784, 15.115)
  ..cubicTo(1.479, 15.05, 1.203, 14.891, 0.994, 14.659)
  ..cubicTo(0.5, 14.111, 0.5, 13.283, 0.5, 12.455)
  ..close();
