//
//  app_haptics.dart
//
//  Every vibration the interface emits goes through here.
//
//  Flutter's `HapticFeedback` ends in `View.performHapticFeedback` with no
//  flags, so the system touch-vibration switch silences it. The Android shell
//  of this bridge fires the same platform effect with both ignore flags — the
//  call exteraless makes for its own interface — and answers whether it
//  actually fired; when it did not, the tick falls back to Flutter's channel
//  instead of disappearing.
//
//  The one preference in [AppHaptics] is the app-wide switch: with it off
//  nothing is sent to either channel, so no surface can buzz on its own.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a tick should feel like. Android strength comes from the platform
/// constants: `light`/`selection` are a key tap, `medium` a long press (the
/// reference client's interface tick), `heavy` a confirmation thump and
/// `vibrate` a rejection buzz.
enum AppHapticKind { light, medium, heavy, selection, vibrate }

/// App-wide haptics: the on/off switch plus the delivery path.
class AppHaptics extends ChangeNotifier {
  AppHaptics._();

  static final AppHaptics shared = AppHaptics._();

  static const _enabledKey = 'mithka.haptics.enabled.v1';

  /// Carries the tick to the Android shell, which fires the platform haptic
  /// with the ignore flags and reports whether it landed.
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
        if (await channel.invokeMethod<bool>('vibrate', kind.name) ?? false) {
          return;
        }
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
