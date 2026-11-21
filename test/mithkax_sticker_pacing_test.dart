//
//  Mithka X video-sticker pacing: a looping sticker must take its authored
//  time. MDK's video-only clock runs with the presented frames on Android, so
//  the media clock outpaces wall time by (display refresh / stream fps); the
//  meter measures that drift and the correction cancels it. Pickers also draw
//  from their own player budget so a grid animates over a busy chat.
//

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

  test('pickers draw from a pool the chat cannot exhaust', () {
    final chat = LoopingMediaPlayerPool(maximumPlayers: 4);
    final chatLeases = [for (var i = 0; i < 4; i++) chat.tryAcquire()!];
    expect(chat.tryAcquire(), isNull);

    final panelLease = stickerPanelPlayerPool.tryAcquire();
    expect(panelLease, isNotNull);
    expect(stickerPanelPlayerPool.maximumPlayers, greaterThanOrEqualTo(4));

    panelLease!.release();
    for (final lease in chatLeases) {
      lease.release();
    }
  });
}
