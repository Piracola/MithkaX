//
//  startup_trace.dart
//
//  TEMPORARY device-side startup trace (icon-switch cold-start investigation).
//
//  The phone this is debugged on has no adb, so the app records its own launch
//  timeline: Dart appends one line per milestone to the host's trace file, the
//  native side adds Activity/engine/icon events and any uncaught exception.
//  Settings > Developer > Startup diagnostics reads it back as copyable text.
//
//  Remove this file, its channel and the view once the crash is understood.
//

import 'dart:async';

import 'package:flutter/services.dart';

abstract final class StartupTrace {
  static const MethodChannel _channel = MethodChannel('mithka/diagnostics');

  /// Never throws and never awaits: a trace write must not shape the launch it
  /// is measuring, and the channel is absent in unit tests.
  static void log(String tag, String message) {
    unawaited(
      _channel
          .invokeMethod<void>('log', <String, Object?>{
            'tag': tag,
            'message': message,
          })
          .catchError((Object _) {}),
    );
  }

  static Future<Map<String, String>> read() async {
    try {
      final result = await _channel.invokeMapMethod<String, String>('read');
      return result ?? const <String, String>{};
    } catch (_) {
      return const <String, String>{};
    }
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      // No host trace (tests, desktop): nothing to clear.
    }
  }
}
