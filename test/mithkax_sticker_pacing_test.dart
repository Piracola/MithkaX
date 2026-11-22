//
//  Mithka X video-sticker pacing: MDK does not give a video-only stream its
//  authored timing — it loops at the last frame's timestamp, dropping that
//  frame's hold, and can run at the display's frame cadence. Measured on a
//  0.4 s, 12.5 fps sticker one loop came round in 0.34 s (18% fast) while a 3 s
//  sticker lost only one frame per loop, which is why only short, low-frame-rate
//  stickers were reported. Sampling the media clock cannot see it (a 0.4 s clip
//  wraps between two of video_player's 100 ms updates), so whole passes are
//  timed and the playback rate is nudged until one loop takes its duration.
//
//  The same file covers the viewport gate: a sticker only holds a native player
//  while it is on screen.
//

import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/media/looping_media_playback.dart';
import 'package:mithka/media/video_sticker_pacing.dart';

void main() {
  group('StickerPacingController', () {
    test('a 0.34 s pass on a 0.4 s sticker is slowed to real time', () {
      final pacing = StickerPacingController();
      // One window of media time: four passes of a 0.4 s clip.
      double? rate;
      for (var i = 0; i < 4; i++) {
        rate = pacing.pass(
          wall: const Duration(milliseconds: 340),
          media: const Duration(milliseconds: 400),
        );
      }
      expect(rate, closeTo(0.85, 0.01));
    });

    test('playback that already takes its authored time is left alone', () {
      final pacing = StickerPacingController();
      for (var i = 0; i < 4; i++) {
        expect(
          pacing.pass(
            wall: const Duration(milliseconds: 400),
            media: const Duration(milliseconds: 400),
          ),
          isNull,
        );
      }
      expect(pacing.rate, 1);
    });

    test('a 4x fast clip is halved per window, never quartered', () {
      final pacing = StickerPacingController();
      // A window of four 0.4 s passes that each came round in 0.1 s.
      double? rate;
      for (var i = 0; i < 4; i++) {
        rate = pacing.pass(
          wall: const Duration(milliseconds: 100),
          media: const Duration(milliseconds: 400),
        );
      }
      // One step is clamped to 2x, so a wildly fast clip takes two windows.
      expect(rate, closeTo(0.5, 0.001));
    });

    test('a stale completion right after a seek is not a pass', () {
      final pacing = StickerPacingController();
      for (var i = 0; i < 8; i++) {
        expect(
          pacing.pass(
            wall: const Duration(milliseconds: 8),
            media: const Duration(milliseconds: 400),
          ),
          isNull,
        );
      }
      expect(pacing.rate, 1);
    });

    test('a pass far slower than real time never speeds playback past 1x', () {
      final pacing = StickerPacingController();
      double? rate;
      for (var i = 0; i < 4; i++) {
        rate = pacing.pass(
          wall: const Duration(seconds: 30),
          media: const Duration(milliseconds: 400),
        );
      }
      // 1x is the authored pace; a slow backend is not asked to run faster.
      expect(rate, isNull);
      expect(pacing.rate, 1);
    });

    test('reset returns to real time', () {
      final pacing = StickerPacingController();
      for (var i = 0; i < 4; i++) {
        pacing.pass(
          wall: const Duration(milliseconds: 100),
          media: const Duration(milliseconds: 400),
        );
      }
      expect(pacing.rate, lessThan(1));
      pacing.reset();
      expect(pacing.rate, 1);
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
      // Still out of view: no repeated reconcile work on every scroll tick.
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
      expect(
        loopingSurfaceIsOnScreen(rect: Rect.zero, screen: screen),
        isFalse,
      );
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
