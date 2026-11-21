//
//  process_engine.dart
//
//  How many FlutterEngines the current OS process has hosted.
//
//  Android does not give an app one process per launch: finishing the last
//  activity leaves a cached process behind, and the next launch attaches a NEW
//  FlutterEngine (and Dart VM) to it. Everything the previous engine created in
//  NATIVE memory survives that VM — TDLib's clients above all — so the second
//  engine has to know it is a re-entry before it opens the same account
//  databases. Every other platform starts a process per engine.
//

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _appInfoChannel = MethodChannel('mithka/app_info');

/// The Android host counts the FlutterEngines it has attached to this process;
/// this asks it. Answers 1 when the platform has no such notion (each engine
/// owns its process) or the host does not expose the counter.
Future<int> processEngineOrdinal() async {
  if (!Platform.isAndroid) return 1;
  return readEngineOrdinal(_appInfoChannel);
}

/// Reads the host's engine counter for [channel].
///
/// Split out so a widget test can drive the decision with a mocked channel
/// instead of a real Android host.
@visibleForTesting
Future<int> readEngineOrdinal(MethodChannel channel) async {
  try {
    final ordinal = await channel.invokeMethod<int>('engineOrdinal');
    return ordinal == null || ordinal < 1 ? 1 : ordinal;
  } catch (_) {
    // An older host without the method answers notImplemented; treat it as a
    // cold start so the launch never waits on a re-entry reclaim that cannot
    // have anything to reclaim.
    return 1;
  }
}
