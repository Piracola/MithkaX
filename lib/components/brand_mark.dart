import 'package:flutter/widgets.dart';

/// The app mark: one flat glyph filled with the launcher icon's aurora
/// gradient.
///
/// Two palettes ship, because the mark has to sit on both surfaces: the azure
/// fill (the launcher icon's night body) reads on a light page, the frost fill
/// (its day body) glows on a dark one. [brandMarkAssetFor] picks per
/// appearance; the splash always uses [brandMarkFrostAsset] because it sits on
/// the brand gradient.
const String brandMarkAsset = 'assets/brand_mark.png';
const String brandMarkFrostAsset = 'assets/brand_mark_frost.png';

/// The same glyphs with their transparent canvas trimmed away, for layouts
/// that space the mark by its ink rather than by a square box.
const String brandMarkInkAsset = 'assets/brand_mark_ink.png';
const String brandMarkInkFrostAsset = 'assets/brand_mark_ink_frost.png';

/// The square mark for [brightness].
String brandMarkAssetFor(Brightness brightness) =>
    brightness == Brightness.dark ? brandMarkFrostAsset : brandMarkAsset;

/// The canvas-trimmed mark for [brightness].
String brandMarkInkAssetFor(Brightness brightness) =>
    brightness == Brightness.dark ? brandMarkInkFrostAsset : brandMarkInkAsset;
