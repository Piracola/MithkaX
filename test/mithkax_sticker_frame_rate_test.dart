//
//  Mithka X video-sticker frame rate: MDK presents a video-only stream by frame
//  count, so a clip runs at (display refresh / stream fps). A 0.4 s, 12.5 fps
//  sticker wraps faster than the position sampler can resolve — measuring it
//  reports "normal" while it races — so the rate is read out of the container
//  and the playback rate is seeded before the first loop.
//

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/webm_frame_rate.dart';

/// A minimal EBML element: id bytes, a one-byte size, then the payload.
Uint8List _element(int id, List<int> payload) {
  final idBytes = <int>[];
  var remaining = id;
  while (remaining > 0) {
    idBytes.insert(0, remaining & 0xff);
    remaining >>= 8;
  }
  return Uint8List.fromList([...idBytes, 0x80 | payload.length, ...payload]);
}

Uint8List _uint64(int value) => Uint8List.fromList([
  for (var shift = 56; shift >= 0; shift -= 8) (value >> shift) & 0xff,
]);

Uint8List _webm({int? defaultDuration}) {
  final info = _element(0x1549A966, [
    // TimecodeScale: 1 ms.
    ..._element(0x2AD7B1, [0x0f, 0x42, 0x40]),
  ]);
  // Telegram (and ffmpeg) put the frame duration on the track, not in Info.
  final track = _element(0xAE, [
    ..._element(0x86, 'V_VP9'.codeUnits),
    if (defaultDuration != null)
      ..._element(0x23E383, _uint64(defaultDuration)),
  ]);
  final tracks = _element(0x1654AE6B, [...track]);
  final segment = _element(0x18538067, [...info, ...tracks]);
  return Uint8List.fromList([
    ..._element(0x1a45dfa3, [
      0x42,
      0x86,
      0x81,
      0x01,
      0x42,
      0x82,
      0x84,
      0x77,
      0x65,
      0x62,
      0x6d,
    ]),
    ...segment,
  ]);
}

void main() {
  group('webmFrameRate', () {
    test('reads a 12.5 fps header', () {
      expect(webmFrameRate(_webm(defaultDuration: 80000000)), 12.5);
    });

    test('reads a 60 fps header', () {
      expect(
        webmFrameRate(_webm(defaultDuration: 16666667)),
        closeTo(60, 0.01),
      );
    });

    test('a header without DefaultDuration reports nothing', () {
      expect(webmFrameRate(_webm()), isNull);
    });

    test('garbage is not mistaken for a header', () {
      expect(webmFrameRate(Uint8List.fromList([1, 2, 3])), isNull);
      expect(webmFrameRate(Uint8List(0)), isNull);
    });
  });

  group('stickerPacingSeed', () {
    test('a 12.5 fps sticker on a 60 Hz screen plays at 0.208x', () {
      expect(
        stickerPacingSeed(frameRate: 12.5, displayRefreshRate: 60),
        closeTo(0.2083, 0.001),
      );
    });

    test('a 30 fps sticker on a 60 Hz screen plays at 0.5x', () {
      expect(
        stickerPacingSeed(frameRate: 30, displayRefreshRate: 60),
        closeTo(0.5, 0.0001),
      );
    });

    test('a sticker that already matches the refresh rate is left alone', () {
      expect(stickerPacingSeed(frameRate: 60, displayRefreshRate: 60), isNull);
      expect(stickerPacingSeed(frameRate: 120, displayRefreshRate: 60), isNull);
    });

    test('a higher refresh rate scales the correction', () {
      expect(
        stickerPacingSeed(frameRate: 30, displayRefreshRate: 120),
        closeTo(0.25, 0.0001),
      );
    });

    test('an unknown or impossible rate seeds nothing', () {
      expect(
        stickerPacingSeed(frameRate: null, displayRefreshRate: 60),
        isNull,
      );
      expect(stickerPacingSeed(frameRate: 0, displayRefreshRate: 60), isNull);
      expect(stickerPacingSeed(frameRate: 30, displayRefreshRate: 0), isNull);
    });
  });
}
