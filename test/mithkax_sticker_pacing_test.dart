//
//  Mithka X video-sticker pacing: MDK stops a video-only clip at its last
//  frame's timestamp, so that frame's hold is dropped every loop — 25% of a
//  five-frame 0.4 s sticker, 1% of a three-second one, which is why only short,
//  low-frame-rate stickers were reported racing. The rate comes out of the WebM
//  header instead of from sampling, because a 0.4 s clip wraps between two of
//  video_player's 100 ms position updates.
//
//  The same file covers the viewport gate: a sticker only holds a native player
//  while it is on screen.
//

import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/looping_media_playback.dart';
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

/// Telegram (and ffmpeg) put the frame duration on the track, not in Info.
Uint8List _webm({int? defaultDuration}) {
  final info = _element(0x1549A966, [
    // TimecodeScale: 1 ms.
    ..._element(0x2AD7B1, [0x0f, 0x42, 0x40]),
  ]);
  final track = _element(0xAE, [
    ..._element(0x86, 'V_VP9'.codeUnits),
    if (defaultDuration != null) ..._element(0x23E383, _uint64(defaultDuration)),
  ]);
  final segment = _element(0x18538067, [...info, ..._element(0x1654AE6B, track)]);
  return Uint8List.fromList([
    ..._element(0x1a45dfa3, [
      0x42, 0x86, 0x81, 0x01, 0x42, 0x82, 0x84, 0x77, 0x65, 0x62, 0x6d,
    ]),
    ...segment,
  ]);
}

void main() {
  group('webmFrameDuration', () {
    test('reads an 80 ms frame from a 12.5 fps header', () {
      expect(
        webmFrameDuration(_webm(defaultDuration: 80000000)),
        const Duration(milliseconds: 80),
      );
    });

    test('a header without DefaultDuration reports nothing', () {
      expect(webmFrameDuration(_webm()), isNull);
    });

    test('garbage is not mistaken for a header', () {
      expect(webmFrameDuration(Uint8List.fromList([1, 2, 3])), isNull);
      expect(webmFrameDuration(Uint8List(0)), isNull);
    });
  });

  group('stickerTailCorrection', () {
    test('a five-frame 0.4 s sticker plays at 0.8x', () {
      expect(
        stickerTailCorrection(
          duration: const Duration(milliseconds: 400),
          frameDuration: const Duration(milliseconds: 80),
        ),
        closeTo(0.8, 0.001),
      );
    });

    test('a three-second sticker is barely touched', () {
      expect(
        stickerTailCorrection(
          duration: const Duration(seconds: 3),
          frameDuration: const Duration(milliseconds: 33),
        ),
        closeTo(0.989, 0.001),
      );
    });

    test('an unknown frame duration leaves the clip alone', () {
      expect(
        stickerTailCorrection(
          duration: const Duration(milliseconds: 400),
          frameDuration: null,
        ),
        isNull,
      );
    });

    test('a header claiming a frame longer than the clip is ignored', () {
      expect(
        stickerTailCorrection(
          duration: const Duration(milliseconds: 400),
          frameDuration: const Duration(milliseconds: 400),
        ),
        isNull,
      );
      expect(
        stickerTailCorrection(
          duration: const Duration(milliseconds: 100),
          frameDuration: const Duration(milliseconds: 50),
        ),
        isNull,
      );
    });
  });

  group('StickerPacingMeter', () {
    test('a moving clock counts forward progress', () {
      final meter = StickerPacingMeter(startPosition: Duration.zero)..start();
      for (var tick = 1; tick <= 15; tick++) {
        meter.tick(Duration(milliseconds: (tick % 8) * 100), const Duration(milliseconds: 800));
      }
      expect(meter.mediaElapsed, const Duration(milliseconds: 1500));
    });
  });

  group('loopingSurfaceIsOnScreen', () {
    const screen = Size(400, 800);

    test('a sticker inside the viewport plays', () {
      expect(
        loopingSurfaceIsOnScreen(
          rect: const Rect.fromLTWH(20, 300, 160, 160),
          screen: screen,
        ),
        isTrue,
      );
    });

    test('a cached child above the viewport does not hold a player', () {
      expect(
        loopingSurfaceIsOnScreen(
          rect: const Rect.fromLTWH(20, -400, 160, 160),
          screen: screen,
        ),
        isFalse,
      );
    });

    test('the margin keeps a sticker alive across a short overscroll', () {
      // Ends 60 px above the viewport: gone, but still inside the margin.
      const rect = Rect.fromLTWH(20, -220, 160, 160);
      expect(loopingSurfaceIsOnScreen(rect: rect, screen: screen), isFalse);
      expect(
        loopingSurfaceIsOnScreen(rect: rect, screen: screen, margin: 96),
        isTrue,
      );
    });

    test('a sticker hands its player back when it leaves and asks again', () {
      final visibility = LoopingSurfaceVisibility(margin: 64);
      expect(visibility.isOnScreen, isTrue);
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, 300, 160, 160),
          screen: screen,
        ),
        isFalse,
      );
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, -600, 160, 160),
          screen: screen,
        ),
        isTrue,
      );
      expect(visibility.isOnScreen, isFalse);
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, -600, 160, 160),
          screen: screen,
        ),
        isFalse,
      );
      expect(
        visibility.update(
          rect: const Rect.fromLTWH(0, 100, 160, 160),
          screen: screen,
        ),
        isTrue,
      );
      expect(visibility.isOnScreen, isTrue);
    });

    test('a surface without a render box keeps its current state', () {
      final visibility = LoopingSurfaceVisibility();
      expect(visibility.update(rect: null, screen: screen), isFalse);
      expect(visibility.isOnScreen, isTrue);
    });

    test('an unlaid-out surface is not treated as visible', () {
      expect(loopingSurfaceIsOnScreen(rect: Rect.zero, screen: screen), isFalse);
    });
  });

  test('the sticker budget covers a full viewport of stickers', () {
    // A sticker picker page shows a dozen or more cells at once; anything
    // smaller is what left only the first cell of the grid animating.
    expect(stickerPlayerPool.maximumPlayers, greaterThanOrEqualTo(20));
    final leases = [
      for (var i = 0; i < 12; i++) stickerPlayerPool.tryAcquire(),
    ];
    expect(leases, everyElement(isNotNull));
    for (final lease in leases) {
      lease!.release();
    }
  });
}
