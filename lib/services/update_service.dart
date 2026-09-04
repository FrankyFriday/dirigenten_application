import 'dart:async';
import 'dart:io';

import '../models/update_info.dart';
import '../services/download_service.dart';
import '../services/signature_service.dart';
import '../utils/logger.dart';

/// Kümmert sich ums Herunterladen eines per WebSocket angekündigten
/// Releases.
class UpdateService {
  final DownloadService _downloadService;

  UpdateService(this._downloadService);

  /// Lädt die APK für [updateInfo] herunter und liefert den lokalen
  /// Dateipfad zurück (oder null bei Fehler).
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo,
    StreamController<double> progressController,
  ) async {
    UpdateLogger.info('========================================');
    UpdateLogger.info('UPDATE DOWNLOAD REQUEST');
    UpdateLogger.info('Server-Version: ${updateInfo.version}');
    UpdateLogger.info('APK-URL: ${updateInfo.url}');

    try {
      final fileName =
          DownloadService.generateFileName(updateInfo.version);

      UpdateLogger.info('Generierter Dateiname: $fileName');
      UpdateLogger.info('Starte Download...');

      final filePath = await _downloadService.downloadFile(
        updateInfo.url,
        fileName,
        progressController,
      );

      if (filePath == null) {
        UpdateLogger.error(
          'Download fehlgeschlagen: kein Dateipfad zurückgegeben.',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      UpdateLogger.info('Download erfolgreich!');
      UpdateLogger.info('Lokaler Dateipfad: $filePath');

      // ------------------------------------------------------------
      // APK EXISTENZ PRÜFEN
      // ------------------------------------------------------------

      final file = File(filePath);

      final exists = await file.exists();

      UpdateLogger.info('APK vorhanden: $exists');

      if (!exists) {
        UpdateLogger.error(
          'Download meldet Erfolg, aber APK wurde nicht gefunden!',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      // ------------------------------------------------------------
      // APK GRÖSSE PRÜFEN
      // ------------------------------------------------------------

      final fileSize = await file.length();

      UpdateLogger.info(
        'APK Größe: $fileSize Bytes',
      );

      if (fileSize <= 0) {
        UpdateLogger.error(
          'APK ist leer!',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      UpdateLogger.info('APK ist gültig vorhanden.');

      // ------------------------------------------------------------
      // SIGNATUR DER INSTALLIERTEN APP AUSLESEN
      // ------------------------------------------------------------

      UpdateLogger.info('========================================');
      UpdateLogger.info('SIGNATURE CHECK');
      UpdateLogger.info('Lese Signatur der installierten App...');

      final installedSignature =
          await SignatureService.getInstalledSignature();

      if (installedSignature == null) {
        UpdateLogger.error(
          'Installierte App-Signatur konnte nicht gelesen werden.',
        );
      } else {
        UpdateLogger.info(
          'Installierte App Signatur:',
        );

        UpdateLogger.info(
          installedSignature,
        );
      }

      // ------------------------------------------------------------
      // SIGNATUR DER HERUNTERGELADENEN APK AUSLESEN
      // ------------------------------------------------------------

      UpdateLogger.info(
        'Lese Signatur der heruntergeladenen APK...',
      );

      final apkInfo =
          await SignatureService.getApkSignature(filePath);

      if (apkInfo == null) {
        UpdateLogger.error(
          'Signatur der heruntergeladenen APK konnte nicht gelesen werden.',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      final apkPackageName =
          apkInfo['packageName'];

      final apkVersion =
          apkInfo['versionName'];

      final apkSignature =
          apkInfo['signature'];

      UpdateLogger.info(
        'APK Package: $apkPackageName',
      );

      UpdateLogger.info(
        'APK Version: $apkVersion',
      );

      UpdateLogger.info(
        'APK Signatur:',
      );

      UpdateLogger.info(
        '$apkSignature',
      );

      // ------------------------------------------------------------
      // PACKAGE NAME PRÜFEN
      // ------------------------------------------------------------

      UpdateLogger.info('Prüfe Package Name...');

      const expectedPackage =
          'com.example.dirigenten_application';

      if (apkPackageName != expectedPackage) {
        UpdateLogger.error(
          '❌ PACKAGE NAME FALSCH!',
        );

        UpdateLogger.error(
          'Erwartet: $expectedPackage',
        );

        UpdateLogger.error(
          'APK: $apkPackageName',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      UpdateLogger.info(
        '✅ PACKAGE NAME OK',
      );

      // Die APK muss exakt die Version tragen, die der Server angekündigt hat.
      if (apkVersion != updateInfo.version) {
        UpdateLogger.error(
          '❌ VERSION FALSCH: erwartet ${updateInfo.version}, '
          'APK enthält $apkVersion',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      UpdateLogger.info('✅ APK VERSION OK');

      // ------------------------------------------------------------
      // SIGNATUR VERGLEICHEN
      // ------------------------------------------------------------

      UpdateLogger.info(
        'Vergleiche Signaturen...',
      );

      if (installedSignature == null ||
          apkSignature == null) {
        UpdateLogger.error(
          '❌ SIGNATURE CHECK NICHT MÖGLICH',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      if (installedSignature == apkSignature) {
        UpdateLogger.info(
          '✅ SIGNATURE MATCH',
        );

        UpdateLogger.info(
          'Die APK wurde mit demselben Keystore signiert.',
        );

        UpdateLogger.info(
          'Android sollte die APK als Update akzeptieren.',
        );
      } else {
        UpdateLogger.error(
          '❌ SIGNATURE MISMATCH',
        );

        UpdateLogger.error(
          'Die heruntergeladene APK wurde mit einem anderen '
          'Keystore signiert!',
        );

        UpdateLogger.error(
          'Installierte App:',
        );

        UpdateLogger.error(
          installedSignature,
        );

        UpdateLogger.error(
          'Heruntergeladene APK:',
        );

        UpdateLogger.error(
          '$apkSignature',
        );

        UpdateLogger.info('UPDATE DOWNLOAD FAILED');
        UpdateLogger.info('========================================');

        return null;
      }

      UpdateLogger.info(
        '========================================',
      );

      UpdateLogger.info(
        'UPDATE DOWNLOAD SUCCESS',
      );

      UpdateLogger.info(
        'APK ist bereit für Installation.',
      );

      UpdateLogger.info(
        '========================================',
      );

      return filePath;

    } catch (e) {
      UpdateLogger.error(
        'Fehler beim Update-Download',
        e,
      );

      UpdateLogger.info(
        'UPDATE DOWNLOAD FAILED',
      );

      UpdateLogger.info(
        '========================================',
      );

      return null;
    }
  }

  /// Retries an operation with exponential backoff.
  static Future<T> retry<T>(
    Future<T> Function() operation,
    int maxRetries,
    Duration initialDelay,
  ) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        if (attempt >= maxRetries) {
          rethrow;
        }

        UpdateLogger.warning(
          'Retry $attempt failed, '
          'waiting ${delay.inSeconds}s',
        );

        await Future.delayed(delay);

        delay *= 2;
      }
    }

    throw Exception('Max retries exceeded');
  }
}