//
//  video_sticker_pacing.dart
//
//  Closed-loop pacing for a looping video sticker.
//
//  MDK does not give a video-only stream its authored timing: it loops at the
//  last frame's timestamp (dropping that frame's hold time) and a video-only
//  clock can run at the display's frame cadence. Measured on a 0.4 s, 12.5 fps
//  sticker, one loop came round in 0.34 s — 18% fast — while a 3 s sticker lost
//  only one frame per loop and looked right, which is exactly why only short,
//  low-frame-rate stickers were reported.
//
//  Sampling the media clock cannot see this: a 0.4 s clip wraps several times
//  between two of video_player's 100 ms position updates. Timing whole passes
//  can, and averaging a window of passes removes the 100 ms quantization. The
//  loop is therefore driven from [VideoStickerView] (seek to zero, play again)
//  so every pass has a boundary to time, and the rate is nudged until one loop
//  takes the clip's authored duration.
//

/// Accumulates completed passes and reports the playback rate that makes a loop
/// take its authored duration. Bounded: one correction per [window] of media
/// time, and each step is clamped so a single bad sample cannot wreck pacing.
class StickerPacingController {
  StickerPacingController({this.window = const Duration(milliseconds: 1600)});

  /// Media time that must accumulate before the rate is adjusted.
  final Duration window;

  double _rate = 1;
  Duration _wall = Duration.zero;
  Duration _media = Duration.zero;

  double get rate => _rate;

  void reset() {
    _rate = 1;
    _wall = Duration.zero;
    _media = Duration.zero;
  }

  /// Records one finished pass. Returns the new rate when it changed, or null
  /// when the window is still filling or playback is close enough.
  ///
  /// [wall] is the time between the end of the previous pass and the end of
  /// this one (a replay delay included), [media] the clip's authored length.
  double? pass({required Duration wall, required Duration media}) {
    if (wall <= Duration.zero || media <= Duration.zero) return null;
    // A pass that came round in a tenth of its length is stale state from a
    // seek, not playback. Anything slower than that is a genuinely racing clip:
    // the worst observed is about 5x.
    if (wall.inMicroseconds * 10 < media.inMicroseconds) return null;
    _wall += wall;
    _media += media;
    if (_media < window) return null;
    final correction = (_wall.inMicroseconds / _media.inMicroseconds).clamp(
      0.5,
      2.0,
    );
    _wall = Duration.zero;
    _media = Duration.zero;
    final next = (_rate * correction).clamp(0.05, 1.0);
    if ((next - _rate).abs() < 0.01) return null;
    _rate = next;
    return next;
  }
}
