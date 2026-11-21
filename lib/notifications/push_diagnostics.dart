import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../platform/firebase_configuration.dart';
import '../tdlib/td_client.dart';
import 'push_device_registrar.dart';
import 'push_service_settings.dart';

/// Collects a copyable, token-free snapshot of the push pipeline.
///
/// This is a temporary device-side diagnostic: the tester has no adb/logcat,
/// so every platform fact that can explain "service unavailable" must fit in
/// one selectable report. Never include FCM/APNs tokens, WebPush endpoints,
/// auth secrets or API keys in the output.
class PushDiagnostics {
  PushDiagnostics._();

  static const _channel = MethodChannel('mithka/push');
  static const _lastRegistrationKey = 'mithka.push.lastRegistration.v1';

  static Future<String> collect() async {
    final lines = <String>['MithkaX push diagnostics'];

    try {
      final info = await PackageInfo.fromPlatform();
      lines.add('app=${info.version}+${info.buildNumber}');
    } catch (error) {
      lines.add('app=unknown (${_describe(error)})');
    }
    lines.add(
      'platform=${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );

    final settings = PushServiceSettings.shared;
    await settings.ensureInitialized();
    lines.add(
      'selected=${settings.kind.name} resident=${settings.residentNotification} '
      'gatewayHost=${Uri.tryParse(settings.gateway)?.host}',
    );
    final status = PushServiceStatus.shared;
    lines.add(
      'status.error=${status.error} registered=${status.registered} '
      'keepAlive=${status.keepAlive} distributor=${status.distributor}',
    );
    final registrationError = PushDeviceRegistrar.shared.lastRegistrationError;
    if (registrationError != null) {
      lines.add(
        'lastRegistrationError=${registrationError.length <= 400 ? registrationError : '${registrationError.substring(0, 400)}…'}',
      );
    }

    Map<String, dynamic>? native;
    try {
      native = await _channel
          .invokeMapMethod<String, dynamic>('getPushDiagnostics')
          .timeout(const Duration(seconds: 12));
    } catch (error) {
      lines.add('native.diagnostics=ERROR ${_describe(error)}');
    }
    if (native != null) {
      lines.add('native=${const JsonEncoder.withIndent('  ').convert(native)}');
    }

    lines.add(
      'firebaseConfiguration.isAvailable=${await FirebaseConfiguration.isAvailable}',
    );
    try {
      lines.add(
        'compiledOptions.projectId=${DefaultFirebaseOptions.currentPlatform.projectId}',
      );
    } catch (error) {
      lines.add('compiledOptions=ERROR ${_describe(error)}');
    }

    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 12));
      final apps = Firebase.apps;
      lines.add(
        'Firebase.initializeApp=ok apps=${apps.map((app) => '${app.name}:${app.options.projectId}').join(',')}',
      );
    } catch (error) {
      lines.add('Firebase.initializeApp=ERROR ${_describe(error)}');
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        final token = await FirebaseMessaging.instance.getToken().timeout(
          const Duration(seconds: 15),
        );
        lines.add(
          'FCM.getToken=${token == null || token.isEmpty ? 'EMPTY' : 'ok len=${token.length}'}',
        );
      } catch (error) {
        lines.add('FCM.getToken=ERROR ${_describe(error)}');
      }
    } else {
      lines.add('FCM.getToken=skipped (no Firebase app)');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastRegistrationKey);
      if (raw == null || raw.isEmpty) {
        lines.add('lastRegistration=none');
      } else {
        final decoded = jsonDecode(raw);
        final tokens = decoded is Map ? decoded['tokens'] : null;
        final types = <String>[];
        if (tokens is List) {
          for (final token in tokens) {
            if (token is Map) {
              final type = token['@type']?.toString() ?? '?';
              final value = token['token'] ?? token['endpoint'];
              types.add('$type(len=${value is String ? value.length : 0})');
            }
          }
        }
        lines.add(
          'lastRegistration.kind=${decoded is Map ? decoded['kind'] : '?'} '
          'tokens=${types.join(',')}',
        );
      }
    } catch (error) {
      lines.add('lastRegistration=ERROR ${_describe(error)}');
    }

    final client = TdClient.shared;
    lines.add(
      'tdlib.slots=${client.configuredSlots} active=${client.activeClientId} '
      'registered=${client.registeredClientIds.length}',
    );
    return lines.join('\n');
  }

  static String _describe(Object error) {
    final text = switch (error) {
      TimeoutException() => 'TimeoutException: ${error.message}',
      PlatformException() =>
        'PlatformException(${error.code}): ${error.message} details=${error.details}',
      _ => '${error.runtimeType}: $error',
    };
    return text.length <= 400 ? text : '${text.substring(0, 400)}…';
  }
}
