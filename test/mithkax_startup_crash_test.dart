//
//  mithkax_startup_crash_test.dart
//
//  Pins the two device crashes that killed the launch on the loading page, so
//  neither can come back silently:
//
//  1. `ForegroundServiceDidNotStartInTimeException` — every
//     startForegroundService() delivery arms its own five-second timer and
//     only a startForeground() from THAT delivery cancels it
//     (ActiveServices.setServiceForegroundInnerLocked). A latch that answers
//     the first delivery and skips the rest leaves the next timer armed, and
//     the system throws on the main thread → process death.
//  2. `LOG(FATAL)` in Client.cpp `TdReceiver::receive` — td_receive is
//     single-threaded per PROCESS. Killing the receive isolate cannot unwind a
//     native frame it is blocked in (up to 1 s inside td_receive), so a
//     replacement spawned straight after starts a second receiver and the
//     process aborts.
//

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/process_engine.dart';

void main() {
  final service = File(
    'android/app/src/main/kotlin/x/empty/mithka/PushKeepAliveService.kt',
  );
  final td = File('lib/tdlib/td_client.dart');

  late final String kt;
  late final String dart;

  setUpAll(() {
    kt = service.readAsStringSync();
    dart = td.readAsStringSync();
  });

  group('keep-alive service', () {
    test('every start answers startForeground', () {
      expect(
        kt.contains('private var foregroundRequirementSatisfied'),
        isFalse,
        reason:
            'a latch that skips startForeground leaves the next '
            'startForegroundService timer armed → '
            'ForegroundServiceDidNotStartInTimeException',
      );
      final command = kt.substring(
        kt.indexOf('override fun onStartCommand'),
        kt.indexOf('override fun onTaskRemoved'),
      );
      expect(command, contains('goForeground('));
      expect(command, contains('startForeground('), reason: 'via goForeground');
      expect(
        command,
        contains('stopSelf(startId)'),
        reason:
            'a refused startForeground() leaves the timer armed; only taking '
            'the service down cancels it',
      );
    });

    test('startForeground is reached from onStartCommand, not onCreate', () {
      final create = kt.substring(
        kt.indexOf('override fun onCreate'),
        kt.indexOf('override fun onStartCommand'),
      );
      expect(
        create.contains('goForeground'),
        isFalse,
        reason:
            'onCreate is not a startForegroundService delivery; answering '
            'there does not cancel the delivery timer',
      );
      expect(
        kt.contains('ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING'),
        isTrue,
      );
    });
  });

  group('one engine per process', () {
    test('a real exit kills the process', () {
      final activity = File(
        'android/app/src/main/kotlin/x/empty/mithka/MainActivity.kt',
      ).readAsStringSync();
      final destroy = activity.substring(
        activity.indexOf('override fun onDestroy'),
      );
      expect(
        destroy,
        contains('isFinishing && !isChangingConfigurations'),
        reason: 'a configuration change must not take the process down',
      );
      expect(
        destroy,
        contains('MediaPlaybackService.isRunning'),
        reason: 'killing the process while audio plays would cut the music',
      );
      expect(
        destroy,
        contains('android.os.Process.killProcess(android.os.Process.myPid())'),
        reason:
            'TDLib keeps one receive thread per PROCESS in a native static, and '
            'a destroyed Dart VM never releases it, so a second engine in a '
            'cached process aborts on its first td_receive (Client.cpp:285)',
      );
    });

    test('the trace keeps the run that died', () {
      final diagnostics = File(
        'android/app/src/main/kotlin/x/empty/mithka/StartupDiagnostics.kt',
      ).readAsStringSync();
      final start = diagnostics.substring(
        diagnostics.indexOf('fun startProcess'),
        diagnostics.contains('fun trimIfNeeded')
            ? diagnostics.indexOf('fun trimIfNeeded')
            : diagnostics.length,
      );
      expect(
        start.contains('writeText("")'),
        isFalse,
        reason:
            'truncating on process start deletes the tail of the run that just '
            'crashed — the only record a native abort leaves',
      );
      expect(start, contains('trimIfNeeded'));
    });
  });

  group('duplicate launches', () {
    test('a live sibling engine is never treated as a re-entry', () {
      const sibling = ProcessEngineState(ordinal: 2);
      expect(sibling.hasLiveSiblingEngine, isTrue);
      expect(sibling.mayReclaimPreviousEngine, isFalse);

      const reentry = ProcessEngineState(ordinal: 2, destroyedOrdinal: 1);
      expect(reentry.hasLiveSiblingEngine, isFalse);
      expect(reentry.mayReclaimPreviousEngine, isTrue);

      const cold = ProcessEngineState();
      expect(cold.hasLiveSiblingEngine, isFalse);
      expect(cold.mayReclaimPreviousEngine, isFalse);
    });

    test('notification taps use the enabled launcher component', () {
      final notifier = File(
        'android/app/src/main/kotlin/x/empty/mithka/PushFallbackNotifier.kt',
      ).readAsStringSync();
      expect(
        notifier.contains('Intent(app, MainActivity::class.java)'),
        isFalse,
        reason:
            'the alias target is a DIFFERENT component than the running alias, '
            'so the tap starts a second Activity — and a second engine',
      );
      expect(notifier, contains('AppEntry.intent(app)'));
    });

    test('a duplicate instance forwards and closes', () {
      final activity = File(
        'android/app/src/main/kotlin/x/empty/mithka/MainActivity.kt',
      ).readAsStringSync();
      final create = activity.substring(
        activity.indexOf('override fun onCreate(savedInstanceState'),
        activity.indexOf('private fun ensureLauncherAliasEnabled'),
      );
      expect(create, contains('savedInstanceState == null'));
      expect(
        create,
        contains('sibling.receiveForwardedIntent(intent)'),
        reason: 'the deep link or share must not be lost with the duplicate',
      );
      expect(create, contains('closedAsDuplicate = true'));
      expect(
        activity,
        contains('leavingForGood && !closedAsDuplicate'),
        reason:
            'a duplicate closing must not kill the process out from under the '
            'engine the user is actually using',
      );
    });

    test('Dart refuses to boot a second engine in a live process', () {
      final main = File('lib/main.dart').readAsStringSync();
      final bootstrap = main.substring(
        main.indexOf('Future<void> _bootstrapAndRunApp'),
      );
      expect(bootstrap, contains('hasLiveSiblingEngine'));
      expect(
        bootstrap,
        contains('SystemNavigator.pop()'),
        reason:
            'nothing may create TDLib state before the check: the second '
            'engine aborts the process on its first td_receive',
      );
      expect(
        bootstrap.indexOf('hasLiveSiblingEngine'),
        lessThan(bootstrap.indexOf('AuthManager()..start()')),
        reason: 'AuthManager starts TDLib; the guard must come first',
      );
    });
  });

  group('receive pump', () {
    test('the previous isolate exits before a replacement spawns', () {
      final spawn = dart.substring(
        dart.indexOf('Future<void> _spawnReceiveIsolate()'),
        dart.indexOf('Future<void> _spawnReceiveIsolateLocked()'),
      );
      expect(
        spawn,
        contains('_receiveSpawnOperation'),
        reason: 'two overlapping calls would each retire and then spawn',
      );

      final locked = dart.substring(
        dart.indexOf('Future<void> _spawnReceiveIsolateLocked()'),
        dart.indexOf('void restartReceiveIsolate'),
      );
      final retireAt = locked.indexOf('_retireReceiveIsolate()');
      final spawnAt = locked.indexOf('Isolate.spawn(');
      expect(retireAt, greaterThan(0));
      expect(spawnAt, greaterThan(retireAt));
      expect(
        locked.contains('_receiveIsolate?.kill('),
        isFalse,
        reason:
            'killing an isolate blocked inside td_receive cannot unwind that '
            'frame, and a second receiver aborts the whole process',
      );
    });

    test('the isolate leaves its loop through a stop request', () {
      final entry = dart.substring(dart.indexOf('void _receiveEntry(SendPort'));
      expect(
        entry.contains('while (true)'),
        isFalse,
        reason: 'the loop must be able to publish a stop request',
      );
      expect(entry, contains('while (!stopRequested)'));
      expect(entry, contains('_tdReceiveReady'));
      expect(entry, contains('_tdReceiveStopCommand'));
      expect(
        dart,
        contains("'@type': _tdReceiveReadyType"),
        reason: 'the owner must learn the port it can stop the isolate with',
      );
    });

    test('setTdlibParameters goes out once per client', () {
      expect(dart, contains('final Set<int> _parametersSent = {};'));
      expect(
        dart,
        contains('if (!_parametersSent.add(clientId)) return;'),
        reason:
            'TDLib answers a repeat with "Unexpected setTdlibParameters" — the '
            'startup path sent it three times',
      );
      expect(
        dart,
        contains('_parametersSent.remove(clientId);'),
        reason: 'a rejected or closed client must be able to try again',
      );
    });
  });
}
