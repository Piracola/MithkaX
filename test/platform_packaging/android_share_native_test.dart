import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the native half of the inbound share contract.
///
/// These are behaviour, not cosmetics:
/// * the payload lives in the process-wide companion, because a warm attach
///   creates a NEW Activity for the share while Dart's channel handler may have
///   been registered by the previous one;
/// * `initial` must not consume the payload, or a delivery that raced Dart's
///   handler startup is lost for the life of the process;
/// * `copyFiles` must always reply, or Dart's `await` never returns and every
///   later share is ignored (the latch stays set).
void main() {
  final source = File(
    'android/app/src/main/kotlin/x/empty/mithka/MainActivity.kt',
  ).readAsStringSync();

  test('the share payload is process-wide, not per activity', () {
    expect(source, contains('private var incomingSharePayload'));
    expect(source, isNot(contains('private var pendingSharePayload')));
  });

  test('initial() answers without consuming the payload', () {
    expect(source, contains('result.success(incomingSharePayload)'));
    expect(source, isNot(contains('incomingSharePayload = null')));
  });

  test('a copy thread always replies, even when a provider throws', () {
    expect(source, contains('catch (error: Throwable)'));
    expect(source, contains('Unable to copy shared files'));
    // The provider reads belong to the per-file guard: a refused grant must not
    // take the whole batch (or the reply) down with it.
    final copyBody = source.substring(
      source.indexOf('private fun copySharedFiles('),
      source.indexOf('private fun sharedFileName('),
    );
    final tryAt = copyBody.indexOf('try {');
    expect(tryAt, greaterThan(0));
    expect(
      copyBody.indexOf('contentResolver.getType(uri)'),
      greaterThan(tryAt),
    );
    expect(copyBody.indexOf('contentResolver.query('), greaterThan(tryAt));
  });
}
