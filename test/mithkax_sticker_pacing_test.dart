//
//  Mithka X video-sticker pacing: a looping sticker must take its authored
//  time. MDK's video-only clock runs with the presented frames on Android, so
//  the media clock outpaces wall time by (display refresh / stream fps); the
//  meter measures that drift and the correction cancels it.
//
//  Animation is gated by what is on screen, not by a fixed few: every sticker
//  a viewport can show gets a player, and cached children scrolled out of the
//  viewport give theirs back.
//

import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/looping_media_playback.dart';

void main() {
  group('stickerPacingCorrection', () {
    test('a 2.5x clock is held back to the authored duration', () {
      expect(
        stickerPacingCorrection(
          mediaElapsed: const Duration(milliseconds: 3000),
          wallElapsed: const Duration(milliseconds: 1200),
        ),
        closeTo(0.4, 0.001),
      );
    });

    test('a 60 fps sticker that already runs at real time is left alone', () {
      expect(
        stickerPacingCorrection(
          mediaElapsed: const Duration(milliseconds: 1500),
          wallElapsed: const Duration(milliseconds: 1500),
        ),
        isNull,
      );
    });

    test('measurement noise below the threshold is not a correction', () {
      expect(
        stickerPacingCorrection(
          mediaElapsed: const Duration(milliseconds: 1610),
          wallElapsed: const Duration(milliseconds: 1500),
        ),
        isNull,
      );
    });

    test('nonsense samples are ignored', () {
      expect(
        stickerPacingCorrection(
          mediaElapsed: Duration.zero,
          wallElapsed: const Duration(milliseconds: 1500),
        ),
        isNull,
      );
      expect(
        stickerPacingCorrection(
          mediaElapsed: const Duration(milliseconds: 1500),
          wallElapsed: Duration.zero,
        ),
        isNull,
      );
      // A clock that appears 1000x fast is a seek, not a playback rate.
      expect(
        stickerPacingCorrection(
          mediaElapsed: const Duration(seconds: 30),
          wallElapsed: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });
  });

  group('StickerPacingMeter', () {
    test('credits a backwards position as the end of a loop', () {
      final meter = StickerPacingMeter(startPosition: Duration.zero)..start();
      const clip = Duration(seconds: 1);
      meter
        ..tick(const Duration(milliseconds: 500), clip)
        ..tick(const Duration(milliseconds: 900), clip)
        ..tick(const Duration(milliseconds: 100), clip);
      expect(meter.mediaElapsed, const Duration(milliseconds: 1100));
    });

    test('measures several loops inside one window', () {
      final meter = StickerPacingMeter(startPosition: Duration.zero)..start();
      const clip = Duration(milliseconds: 800);
      // Three loops of an 800 ms clip polled every 100 ms, as video_player
      // reports them: the position wraps to zero at the end of each loop.
      for (var tick = 1; tick <= 24; tick++) {
        meter.tick(Duration(milliseconds: (tick % 8) * 100), clip);
      }
      expect(meter.mediaElapsed, const Duration(milliseconds: 2400));
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

    test('an unlaid-out surface is not treated as visible', () {
      expect(
        loopingSurfaceIsOnScreen(rect: Rect.zero, screen: screen),
        isFalse,
      );
    });
  });
}
