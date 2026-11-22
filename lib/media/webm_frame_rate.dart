//
//  webm_frame_rate.dart
//
//  Reads the nominal frame rate out of a WebM header, so a video sticker can
//  be held at its authored pace from the first frame.
//
//  MDK presents a video-only stream by frame count, not by the frame
//  timestamps, on Android: a clip runs at (display refresh / stream fps).
//  Measuring that drift against the wall clock works for clips long enough to
//  fill a sampling window, but a 0.4 s sticker loops several times between two
//  position samples and the measurement aliases back to "normal", which is why
//  short, low-frame-rate stickers kept racing after the measurement fix.
//  The container states the rate outright:
//  Segment > Tracks > TrackEntry > DefaultDuration.
//

import 'dart:typed_data';

const int _segmentId = 0x18538067;
const int _infoId = 0x1549A966;
const int _tracksId = 0x1654AE6B;
const int _trackEntryId = 0xAE;
const int _defaultDurationId = 0x23E383;

/// Telegram video stickers are constant-frame-rate WebM. Returns the nominal
/// frame rate, or null when the header does not state one.
double? webmFrameRate(Uint8List bytes) {
  final defaults = <double>[];
  _walk(bytes, 0, bytes.length, 0, defaults);
  for (final nanoseconds in defaults) {
    if (nanoseconds >= 1000) return 1e9 / nanoseconds;
  }
  return null;
}

/// How much the media clock of a video-only stream runs ahead of real time.
///
/// A clip of [frameRate] fps presented at [displayRefreshRate] frames per
/// second plays [displayRefreshRate]/[frameRate] times too fast; the reciprocal
/// is the playback rate that restores its authored duration. Returns null when
/// the clip is already paced correctly (or the numbers cannot be trusted).
double? stickerPacingSeed({
  required double? frameRate,
  required double displayRefreshRate,
}) {
  if (frameRate == null || !frameRate.isFinite || frameRate < 2) return null;
  if (!displayRefreshRate.isFinite || displayRefreshRate <= 1) return null;
  final speedUp = displayRefreshRate / frameRate;
  if (speedUp < 1.2) return null;
  return (1 / speedUp).clamp(0.05, 1.0);
}

void _walk(
  Uint8List bytes,
  int start,
  int end,
  int depth,
  List<double> defaults,
) {
  if (depth > 4) return;
  final cursor = _Cursor(bytes, start, end);
  while (cursor.offset < end) {
    final id = cursor.readId();
    if (id == null) return;
    final size = cursor.readSize();
    if (size == null) return;
    final payloadStart = cursor.offset;
    // An unknown-size master element runs to the end of its parent.
    final payloadEnd = size < 0 || payloadStart + size > end
        ? end
        : payloadStart + size;
    switch (id) {
      case _segmentId:
      case _infoId:
      case _tracksId:
      case _trackEntryId:
        _walk(bytes, payloadStart, payloadEnd, depth + 1, defaults);
      case _defaultDurationId:
        final value = _readUint(bytes, payloadStart, payloadEnd);
        if (value != null) defaults.add(value.toDouble());
    }
    if (payloadEnd <= payloadStart) return;
    cursor.offset = payloadEnd;
  }
}

int? _readUint(Uint8List bytes, int start, int end) {
  final length = end - start;
  if (length <= 0 || length > 8) return null;
  var value = 0;
  for (var i = start; i < end; i++) {
    value = (value << 8) | bytes[i];
  }
  return value;
}

class _Cursor {
  _Cursor(this.bytes, this.offset, this.end);

  final Uint8List bytes;
  int offset;
  final int end;

  /// EBML ids keep their length marker, so the raw bytes are the id.
  int? readId() {
    final length = _vintLength(_peek());
    if (length < 0 || length > 4 || offset + length > end) return null;
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 8) | bytes[offset + i];
    }
    offset += length;
    return value;
  }

  /// Sizes drop their marker bit. A value of -1 means "unknown".
  int? readSize() {
    final first = _peek();
    final length = _vintLength(first);
    if (length < 0 || offset + length > end) return null;
    var value = first & (0xff >> length);
    var allOnes = value == (0xff >> length);
    for (var i = 1; i < length; i++) {
      final byte = bytes[offset + i];
      if (byte != 0xff) allOnes = false;
      value = (value << 8) | byte;
    }
    offset += length;
    return allOnes ? -1 : value;
  }

  int _peek() => offset < end ? bytes[offset] : 0;

  static int _vintLength(int first) {
    if (first == 0) return -1;
    for (var length = 1; length <= 8; length++) {
      if (first & (0x80 >> (length - 1)) != 0) return length;
    }
    return -1;
  }
}
