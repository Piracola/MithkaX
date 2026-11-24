//
//  app_haptics.dart
//
//  Every vibration the interface emits goes through here.
//
//  Flutter's `HapticFeedback` ends in `View.performHapticFeedback`, which the
//  system touch-vibration switch silences and which is only as strong as the
//  platform's key-tick constant. exteraless vibrates the `Vibrator` itself with
//  Telegram's own waveforms, so it always fires and hits much harder; the
//  Android shell of this bridge ports those waveforms (`HapticsPlugin.kt`),
//  amplitudes included.
//
//  The one preference in [AppHaptics] is the app-wide switch: with it off
//  nothing is sent to either channel, so no surface can buzz on its own.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a tick should feel like, named after the reference client's effects.
/// `light`/`medium`/`heavy` are 7 ms impacts at 65/145/255 amplitude,
/// `selection` is a 1 ms 65 tap and `vibrate` is the two-burst error pattern.
enum AppHapticKind { light, medium, heavy, selection, vibrate }

/// App-wide haptics: the on/off switch plus the delivery path.
class AppHaptics extends ChangeNotifier {
  AppHaptics._();

  static final AppHaptics shared = AppHaptics._();

  static const _enabledKey = 'mithka.haptics.enabled.v1';

  /// Carries the tick to the Android shell, which plays the reference
  /// client's waveform through the Vibrator.
  static const MethodChannel channel = MethodChannel('mithka/haptics');

  SharedPreferences? _prefs;
  bool _enabled = true;

  /// Whether the app may vibrate at all.
  bool get enabled => _enabled;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _enabled = prefs.getBool(_enabledKey) ?? true;
    notifyListeners();
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    unawaited(_prefs?.setBool(_enabledKey, value) ?? Future<void>.value());
    notifyListeners();
  }

  /// Fires one tick, if the app is allowed to vibrate.
  ///
  /// Android goes through the native bridge; every other platform (and a test
  /// harness without the plugin) keeps Flutter's own channel.
  Future<void> fire(AppHapticKind kind) async {
    if (!_enabled) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await channel.invokeMethod<void>('vibrate', kind.name);
        return;
      } on MissingPluginException {
        // No native shell (tests, an engine built before this bridge).
      } on PlatformException {
        // Fall through to the framework channel rather than swallow the tick.
      }
    }
    await _flutterFeedback(kind);
  }

  Future<void> _flutterFeedback(AppHapticKind kind) {
    return switch (kind) {
      AppHapticKind.light => HapticFeedback.lightImpact(),
      AppHapticKind.medium => HapticFeedback.mediumImpact(),
      AppHapticKind.heavy => HapticFeedback.heavyImpact(),
      AppHapticKind.selection => HapticFeedback.selectionClick(),
      AppHapticKind.vibrate => HapticFeedback.vibrate(),
    };
  }

  // Call-site shorthands, named after `HapticFeedback` so a surface reads the
  // same as before while every call is gated by the one switch.
  static Future<void> lightImpact() => shared.fire(AppHapticKind.light);

  static Future<void> mediumImpact() => shared.fire(AppHapticKind.medium);

  static Future<void> heavyImpact() => shared.fire(AppHapticKind.heavy);

  static Future<void> selectionClick() => shared.fire(AppHapticKind.selection);

  static Future<void> vibrate() => shared.fire(AppHapticKind.vibrate);
}
