import 'package:flutter/services.dart';

import '../utils/logger.dart';

class SignatureService {
  static const MethodChannel _channel =
      MethodChannel('app.signature');

  /// Signatur der aktuell installierten App
  static Future<String?> getInstalledSignature() async {
    try {
      final signature =
          await _channel.invokeMethod<String>(
        'getInstalledSignature',
      );

      UpdateLogger.info(
        'Installierte App Signatur: $signature',
      );

      return signature;
    } catch (e) {
      UpdateLogger.error(
        'Fehler beim Lesen der installierten Signatur',
        e,
      );

      return null;
    }
  }

  /// Signatur der heruntergeladenen APK
  static Future<Map<String, dynamic>?> getApkSignature(
    String apkPath,
  ) async {
    try {
      final result =
          await _channel.invokeMethod<Map>(
        'getApkSignature',
        {
          'path': apkPath,
        },
      );

      if (result == null) {
        return null;
      }

      final data =
          Map<String, dynamic>.from(result);

      UpdateLogger.info(
        'APK Package: ${data['packageName']}',
      );

      UpdateLogger.info(
        'APK Version: ${data['versionName']}',
      );

      UpdateLogger.info(
        'APK Signatur: ${data['signature']}',
      );

      return data;
    } catch (e) {
      UpdateLogger.error(
        'Fehler beim Lesen der APK-Signatur',
        e,
      );

      return null;
    }
  }
}