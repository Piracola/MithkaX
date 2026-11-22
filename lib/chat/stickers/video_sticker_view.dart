//
//  video_sticker_view.dart
//
//  Plays a Telegram `.webm` (VP9 + alpha) video sticker, looping + muted.
//  Android 14+ renders the supplied static thumbnail instead of loading FVP's
//  MDK decoder: native surface creation is unstable on those releases.
//

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../components/photo_avatar.dart';
import '../../media/looping_media_playback.dart';
import '../../media/video_playback_reporting.dart';
import '../../media/webm_frame_rate.dart';
import '../../tdlib/td_client.dart';
import '../../tdlib/td_image_loader.dart';
import '../../tdlib/td_models.dart';

/// FVP's Android MDK decoder can crash while creating a native video surface
/// on Android 14 and later. Video stickers always include a static thumbnail,
/// so prefer that safe representation there rather than risking the process.
@visibleForTesting
bool shouldUseStaticAndroidVideoStickerFallback(int? sdkInt) =>
    sdkInt == null || sdkInt >= 34;

class VideoStickerView extends StatefulWidget {
  const VideoStickerView({
    super.key,
    required this.file,
    this.fallback,
    this.onReady,
    this.pool,
  });
  final TdFileRef file;
  final TdFileRef? fallback;
  final VoidCallback? onReady;

  /// Native-player budget to draw from. Stickers and their pickers share
  /// [stickerPlayerPool]; other looping surfaces keep their own budget.
  final LoopingMediaPlayerPool? pool;

  @override
  State<VideoStickerView> createState() => _VideoStickerViewState();
}

class _VideoStickerViewState extends State<VideoStickerView>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  int? _loadedId;
  String? _loadedLocalPath;
  int? _loadedSlot;
  bool _fallbackOnly = false;
  bool _tickerEnabled = false;
  bool _appIsActive = true;
  final LoopingSurfaceVisibility _visibility = LoopingSurfaceVisibility(
    margin: _visibilityMargin,
  );
  bool _visibilityCheckScheduled = false;
  ScrollPosition? _scrollPosition;
  bool _loadPending = false;
  int _generation = 0;
  LoopingMediaPlayerLease? _lease;
  LoopingMediaPlayerWaiter? _leaseWaiter;
  VideoPlayerController? _initializingController;
  VideoPlaybackDiagnostics? _playbackDiagnostics;
  Timer? _loopReplayTimer;
  StickerPacingMeter? _pacing;
  double _pacingSpeed = 1;
  int _pacingPasses = 0;

  /// A measurement window long enough to average out video_player's 100 ms
  /// position polling, short enough that one sped-up loop is all the user sees.
  static const _pacingWindow = Duration(milliseconds: 1500);
  static const _maxPacingPasses = 2;

  /// Below this loop period, a wrap can fall between two position samples and
  /// the measured rate aliases back to 1.0. Short stickers are therefore paced
  /// from the frame rate in their header first, which stretches the loop into
  /// something the meter can resolve.
  static const _minMeasurableLoop = Duration(milliseconds: 600);

  static final Map<String, double?> _frameRateCache = <String, double?>{};

  /// Keeps a sticker alive across a short overscroll instead of tearing its
  /// decoder down and rebuilding it on the way back.
  static const double _visibilityMargin = 64;

  static Future<bool>? _androidNeedsStaticFallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appIsActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    addLoopingMediaPlaybackContextListener(_handlePlaybackContextChanged);
  }

  bool get _isEligible =>
      _visibility.isOnScreen &&
      loopingMediaPlaybackIsEligible(
        tickerEnabled: _tickerEnabled,
        appIsActive: _appIsActive,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _attachScrollListener();
    _scheduleVisibilityCheck();
    _reconcilePlayback(rebuildOnRelease: false);
  }

  @override
  void didUpdateWidget(VideoStickerView old) {
    super.didUpdateWidget(old);
    _scheduleVisibilityCheck();
    _reconcilePlayback(rebuildOnRelease: false);
  }

  /// Every sticker in a chat or a picker page lives in a scrollable, and only
  /// the ones inside the viewport should own a native player.
  void _attachScrollListener() {
    final position = Scrollable.maybeOf(context)?.position;
    if (identical(position, _scrollPosition)) return;
    _scrollPosition?.removeListener(_scheduleVisibilityCheck);
    _scrollPosition = position;
    _scrollPosition?.addListener(_scheduleVisibilityCheck);
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled || !mounted) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      final media = MediaQuery.maybeOf(context);
      final box = context.findRenderObject();
      if (media == null || box is! RenderBox || !box.attached || !box.hasSize) {
        return;
      }
      final changed = _visibility.update(
        rect: box.localToGlobal(Offset.zero) & box.size,
        screen: media.size,
      );
      if (!changed) return;
      _reconcilePlayback();
    });
  }

  @override
  void didChangeMetrics() {
    // Keyboard insets, rotation, and a sheet sliding over the list all move
    // every sticker without scrolling it.
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;
    _reconcilePlayback();
  }

  void _handlePlaybackContextChanged() {
    if (!mounted) return;
    _reconcilePlayback();
  }

  void _reconcilePlayback({bool rebuildOnRelease = true}) {
    final slot = TdClient.shared.activeSlot;
    final sourceChanged =
        _loadedId != widget.file.id ||
        _loadedLocalPath != widget.file.localPath ||
        _loadedSlot != slot;
    if (!_isEligible || sourceChanged) {
      _releasePlayback(rebuild: rebuildOnRelease);
    }
    if (!_isEligible) return;
    if (sourceChanged) {
      _playbackDiagnostics = VideoPlaybackDiagnostics(
        location: VideoPlaybackLocation.sticker,
        mimeType: 'video/webm',
      );
      _loadedId = widget.file.id;
      _loadedLocalPath = widget.file.localPath;
      _loadedSlot = slot;
      _fallbackOnly = false;
      _pacingSpeed = 1;
      _pacingPasses = 0;
    }
    if (!_fallbackOnly &&
        _controller == null &&
        !_loadPending &&
        _leaseWaiter == null) {
      _requestPlaybackLease();
    }
  }

  void _requestPlaybackLease() {
    if (!_isEligible ||
        _fallbackOnly ||
        _loadPending ||
        _controller != null ||
        _leaseWaiter != null) {
      return;
    }
    final ref = widget.file;
    final slot = TdClient.shared.activeSlot;
    final generation = ++_generation;
    final pool = widget.pool ?? stickerPlayerPool;
    final lease = pool.tryAcquire();
    if (lease != null) {
      _startLoad(lease, generation, ref, slot);
      return;
    }

    late final LoopingMediaPlayerWaiter waiter;
    waiter = pool.waitForLease((grantedLease) {
      if (identical(_leaseWaiter, waiter)) _leaseWaiter = null;
      if (!_ownsAttempt(generation, ref, slot)) {
        grantedLease.release();
        return;
      }
      _startLoad(grantedLease, generation, ref, slot);
    });
    _leaseWaiter = waiter;
  }

  void _startLoad(
    LoopingMediaPlayerLease lease,
    int generation,
    TdFileRef ref,
    int slot,
  ) {
    if (!_ownsAttempt(generation, ref, slot)) {
      lease.release();
      return;
    }
    _lease = lease;
    _loadPending = true;
    unawaited(_loadWithLease(lease, generation, ref, slot));
  }

  Future<void> _loadWithLease(
    LoopingMediaPlayerLease lease,
    int generation,
    TdFileRef ref,
    int slot,
  ) async {
    if (!_ownsLoad(generation, ref, slot, lease)) {
      _clearLoadLease(lease);
      return;
    }

    final fallbackOnly = await _useStaticFallbackOnly();
    if (!_ownsLoad(generation, ref, slot, lease)) {
      _clearLoadLease(lease);
      return;
    }
    if (fallbackOnly) {
      _fallbackOnly = true;
      _clearLoadLease(lease);
      setState(() {});
      widget.onReady?.call();
      return;
    }

    final path = await TdFileCenter.shared.pathFor(ref);
    if (!_ownsLoad(generation, ref, slot, lease)) {
      _clearLoadLease(lease);
      return;
    }
    if (path == null) {
      _clearLoadLease(lease);
      return;
    }

    final c = VideoPlayerController.file(
      File(path),
      videoPlayerOptions: mutedLoopingVideoPlayerOptions(),
    );
    _initializingController = c;
    final diagnostics = _playbackDiagnostics!;
    diagnostics.beginAttempt(
      source: VideoPlaybackSource.file,
      viewType: c.viewType,
    );
    try {
      // MDK (via fvp) may ignore a loop flag applied once the media is
      // prepared (wang-bin/fvp#394), so record it first; video_player applies
      // it while handling the initialized event. A completed clip is also
      // replayed from the value listener below, so the sticker loops even on
      // backends that still ignore the flag.
      await c.setLooping(true);
      await c.initialize();
      diagnostics.initialized(value: c.value);
      await c.setVolume(0);
      disableLoopingMediaAudioTracks(c);
      applyWebmLoopingDecoderOverride(c);
      if (!_ownsLoad(generation, ref, slot, lease)) {
        await _disposeInitializingLoad(c, lease);
        return;
      }
      await c.play();
    } catch (error) {
      final ownsCurrentSource = _ownsLoad(generation, ref, slot, lease);
      if (ownsCurrentSource) {
        diagnostics.recordFailure(
          error,
          stage: VideoFailureStage.initialization,
        );
        diagnostics.reportTerminal();
        _fallbackOnly = true;
      }
      await _disposeInitializingLoad(c, lease);
      if (ownsCurrentSource && _ownsAttempt(generation, ref, slot)) {
        setState(() {});
        widget.onReady?.call();
      }
      return;
    }
    if (!_ownsLoad(generation, ref, slot, lease)) {
      await _disposeInitializingLoad(c, lease);
      return;
    }
    if (identical(_initializingController, c)) {
      _initializingController = null;
    }
    _loadPending = false;
    _pacing = null;
    unawaited(_startStickerPacing(c, path));
    c.addListener(() {
      if (!_ownsAttempt(generation, ref, slot)) return;
      final value = c.value;
      if (value.hasError) {
        diagnostics.recordFailure(
          value.errorDescription,
          stage: VideoFailureStage.playback,
        );
        diagnostics.reportTerminal();
        return;
      }
      _measureStickerPacing(c);
      // A backend that ignored setLooping completes the clip once and stops
      // on its last frame; a video sticker must loop forever. Replay it from
      // the start, but only after video_player's own `completed` handler has
      // paused and parked the clip on its last frame, or the sticker briefly
      // flashes that frame at every wrap.
      if (value.isCompleted && !value.isPlaying) {
        _loopReplayTimer ??= Timer(_loopReplayDelay, () {
          _loopReplayTimer = null;
          unawaited(_replayCompletedSticker(c, generation, ref, slot));
        });
      }
    });
    setState(() => _controller = c);
    widget.onReady?.call();
  }

  static const _loopReplayDelay = Duration(milliseconds: 50);

  /// Holds a video sticker at its authored pace from the first frame.
  ///
  /// The frame rate comes out of the WebM header: a 12.5 fps sticker looping in
  /// 0.4 s is faster than the position sampler can resolve, so measuring it
  /// reports "normal" while it races. The seed is exact for a
  /// constant-frame-rate clip; the meter below then refines it (and covers
  /// clips whose header states no rate).
  Future<void> _startStickerPacing(VideoPlayerController c, String path) async {
    final frameRate = await _frameRateOf(path);
    final seed = stickerPacingSeed(
      frameRate: frameRate,
      displayRefreshRate: _displayRefreshRate(),
    );
    if (seed != null) {
      if (!mounted || !identical(_controller, c)) return;
      _pacingSpeed = seed;
      await _applyStickerPacing(c, seed);
    }
    if (!mounted || !identical(_controller, c)) return;
    _pacing = StickerPacingMeter(startPosition: c.value.position)..start();
  }

  static Future<double?> _frameRateOf(String path) async {
    if (_frameRateCache.containsKey(path)) return _frameRateCache[path];
    double? rate;
    try {
      rate = webmFrameRate(await File(path).readAsBytes());
    } catch (_) {
      rate = null;
    }
    return _frameRateCache[path] = rate;
  }

  /// Video-only streams are presented at the display's refresh rate, so the
  /// correction depends on it rather than on an assumed 60 Hz.
  static double _displayRefreshRate() {
    var best = 60.0;
    for (final display in PlatformDispatcher.instance.displays) {
      final rate = display.refreshRate;
      if (rate.isFinite && rate > best) best = rate;
    }
    return best;
  }

  /// Holds a video sticker at its authored duration.
  ///
  /// MDK advances the clock of a video-only stream with each presented frame
  /// instead of by the frame timestamps, so a sticker runs at (display refresh
  /// / stream fps) on Android: 60 fps stickers look right, 24–30 fps ones
  /// finish in a fraction of their duration. The drift is measured against the
  /// wall clock and cancelled with the decoder's playback rate; a second
  /// window refines an estimate the first one got wrong. Bounded to two
  /// windows so a backend without rate control is left alone.
  void _measureStickerPacing(VideoPlayerController c) {
    final pacing = _pacing;
    if (pacing == null || _pacingPasses >= _maxPacingPasses) return;
    final value = c.value;
    if (!value.isPlaying || value.hasError) return;
    final loopMicros = value.duration.inMicroseconds / _pacingSpeed;
    if (loopMicros < _minMeasurableLoop.inMicroseconds) return;
    pacing.tick(value.position, value.duration);
    if (pacing.wallElapsed < _pacingWindow) return;
    final correction = stickerPacingCorrection(
      mediaElapsed: pacing.mediaElapsed,
      wallElapsed: pacing.wallElapsed,
    );
    _pacing = StickerPacingMeter(startPosition: value.position)..start();
    _pacingPasses++;
    if (correction == null) return;
    _pacingSpeed = (_pacingSpeed * correction).clamp(0.1, 1.0);
    unawaited(_applyStickerPacing(c, _pacingSpeed));
  }

  Future<void> _applyStickerPacing(
    VideoPlayerController c,
    double speed,
  ) async {
    try {
      await c.setPlaybackSpeed(speed);
      debugPrint('video sticker pacing: playback rate $speed');
    } catch (_) {
      // Backends without rate control keep their own pacing.
    }
  }

  Future<void> _replayCompletedSticker(
    VideoPlayerController controller,
    int generation,
    TdFileRef ref,
    int slot,
  ) async {
    if (!mounted ||
        !identical(_controller, controller) ||
        !_ownsAttempt(generation, ref, slot)) {
      return;
    }
    final value = controller.value;
    if (!value.isCompleted || value.isPlaying || value.hasError) return;
    try {
      await controller.seekTo(Duration.zero);
      await controller.play();
    } catch (_) {
      // A failed replay leaves the last frame up; the next reconcile retries.
    }
  }

  bool _ownsAttempt(int generation, TdFileRef ref, int slot) =>
      mounted &&
      _isEligible &&
      generation == _generation &&
      _loadedId == ref.id &&
      _loadedLocalPath == ref.localPath &&
      _loadedSlot == slot &&
      slot == TdClient.shared.activeSlot;

  bool _ownsLoad(
    int generation,
    TdFileRef ref,
    int slot,
    LoopingMediaPlayerLease lease,
  ) =>
      _ownsAttempt(generation, ref, slot) &&
      identical(_lease, lease) &&
      !lease.isReleased;

  void _clearLoadLease(LoopingMediaPlayerLease lease) {
    if (identical(_lease, lease)) {
      _lease = null;
      _loadPending = false;
      lease.release();
    }
  }

  Future<void> _disposeInitializingLoad(
    VideoPlayerController controller,
    LoopingMediaPlayerLease lease,
  ) async {
    if (!identical(_initializingController, controller)) return;
    _initializingController = null;
    final ownsLease = identical(_lease, lease);
    if (ownsLease) {
      _lease = null;
    }
    try {
      await controller.dispose();
    } catch (_) {
      // Native teardown failures must not become uncaught async errors.
    } finally {
      if (ownsLease) {
        if (_lease == null && _initializingController == null) {
          _loadPending = false;
        }
        lease.release();
      }
    }
  }

  void _releasePlayback({bool rebuild = true}) {
    ++_generation;
    _leaseWaiter?.cancel();
    _leaseWaiter = null;
    _loadPending = false;
    _loopReplayTimer?.cancel();
    _loopReplayTimer = null;
    _pacing = null;
    final controller = _controller;
    final initializingController = _initializingController;
    final lease = _lease;
    _controller = null;
    _initializingController = null;
    _lease = null;
    final controllers = <VideoPlayerController>{
      ?controller,
      ?initializingController,
    };
    if (controllers.isEmpty) {
      lease?.release();
    } else {
      unawaited(_disposeReleasedControllers(controllers, lease));
    }
    if (controller != null && rebuild && mounted) setState(() {});
  }

  Future<void> _disposeReleasedControllers(
    Set<VideoPlayerController> controllers,
    LoopingMediaPlayerLease? lease,
  ) async {
    try {
      await Future.wait(
        controllers.map((current) async {
          try {
            await current.dispose();
          } catch (_) {
            // Continue tearing down the remaining native players.
          }
        }),
      );
    } finally {
      lease?.release();
    }
  }

  static Future<bool> _useStaticFallbackOnly() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return _androidNeedsStaticFallback ??= _androidSdkInt().then(
      shouldUseStaticAndroidVideoStickerFallback,
    );
  }

  static Future<int?> _androidSdkInt() async {
    try {
      final info = await const MethodChannel(
        'mithka/app_info',
      ).invokeMapMethod<String, Object?>('info');
      final sdkInt = info?['sdkInt'];
      return sdkInt is int ? sdkInt : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_scheduleVisibilityCheck);
    _scrollPosition = null;
    WidgetsBinding.instance.removeObserver(this);
    removeLoopingMediaPlaybackContextListener(_handlePlaybackContextChanged);
    _releasePlayback(rebuild: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _fallbackOnly) {
      final fallback = widget.fallback;
      if (fallback == null) return const SizedBox.expand();
      return TDImage(photo: fallback, cornerRadius: 0, fit: BoxFit.contain);
    }
    return VideoPlayer(c);
  }
}
