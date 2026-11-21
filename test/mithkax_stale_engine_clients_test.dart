//
//  stale_engine_clients_test.dart
//
//  Pins the Android re-entry repair: a finished activity's process is reused,
//  so the app can get a SECOND FlutterEngine while the first engine's native
//  TDLib clients are still alive and holding every account's binlog lock.
//
//  - the host's engine counter decides whether a reclaim is due, and an
//    unknown host (no method, exception, 0) must read as a cold start;
//  - the reclaim closes the persisted ids and WAITS for authorizationStateClosed
//    before the replacements are created on the same directories;
//  - live ids are persisted in release too (the gate used to be debug-only);
//  - engine teardown closes the native clients while the VM can still send.
//

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/platform/process_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mithka/app_info');

  void answer(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  }

  group('engine ordinal', () {
    test('a re-entry reports the host counter', () async {
      answer((call) async => call.method == 'engineOrdinal' ? 2 : null);

      expect(await readEngineOrdinal(channel), 2);
    });

    test('an older host without the method reads as a cold start', () async {
      answer((call) async => throw MissingPluginException());

      expect(await readEngineOrdinal(channel), 1);
    });

    test('a zero or negative answer reads as a cold start', () async {
      for (final answerValue in <Object?>[0, -1, null]) {
        answer((call) async => answerValue);

        expect(await readEngineOrdinal(channel), 1);
      }
    });
  });

  group('startup reclaim (source scan)', () {
    final td = File('lib/tdlib/td_client.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    String between(String start, String end) {
      final from = td.indexOf(start);
      expect(from, isNonNegative, reason: 'missing $start');
      final to = td.indexOf(end, from);
      expect(to, greaterThan(from), reason: 'missing $end after $start');
      return td.substring(from, to);
    }

    test('the reclaim runs before any replacement client is created', () {
      final reclaimCall = td.indexOf('await _reclaimStaleEngineClients();');
      final firstClient = td.indexOf('_bindings.createClientId()');
      expect(reclaimCall, isNonNegative);
      expect(firstClient, isNonNegative);
      expect(
        reclaimCall,
        lessThan(firstClient),
        reason:
            'opening the same database directory before the previous engine '
            'released it is exactly the loading-page failure',
      );
    });

    test('the reclaim waits for the closed acknowledgement, not a timer', () {
      final body = between(
        'Future<void> _reclaimStaleEngineClients()',
        'void closeClientsForNativeEngineDetach()',
      );
      expect(
        body,
        contains('_clientClosedWaiters[id] ??='),
        reason: 'authorizationStateClosed is the only release signal',
      );
      expect(body, contains('_tdCloseRequest'));
      expect(body, contains('.timeout('));
      expect(
        body.contains('Future<void>.delayed'),
        isFalse,
        reason: 'a fixed sleep cannot tell whether the lock is gone',
      );
    });

    test('the gate is the host counter, not the build mode', () {
      final gate = between(
        '// Android can attach a SECOND FlutterEngine',
        'final storedBotApiAccounts',
      );
      expect(gate, contains('processEngineOrdinal() > 1'));
      expect(gate, contains('kDebugMode ||'));
      expect(gate, contains('await _reclaimStaleEngineClients();'));
    });

    test('live client ids are persisted in release builds too', () {
      expect(
        td.contains('if (kDebugMode) unawaited(_persistLiveClientIds());'),
        isFalse,
        reason: 'a release build must record what a later engine has to close',
      );
      expect(td, contains('unawaited(_persistLiveClientIds());'));
      expect(td.contains('_persistDebugLiveClientIds'), isFalse);
    });

    test('engine teardown closes the native clients before the VM dies', () {
      expect(
        main.contains(
          'state == AppLifecycleState.detached &&\n'
          '        defaultTargetPlatform == TargetPlatform.android',
        ),
        isTrue,
        reason:
            'only the process-reusing platform should close clients at detach; '
            'desktop windows share the primary engine',
      );
      expect(main, contains('closeClientsForNativeEngineDetach()'));
      expect(
        td,
        contains(
          'if (_proxyTransport != null || _isShuttingDown || _shutdownComplete)',
        ),
      );
    });
  });
}
