import 'dart:async';
import '../models/update_info.dart';
import '../services/download_service.dart';
import '../utils/logger.dart';

/// Kümmert sich ums Herunterladen eines per WebSocket angekündigten
/// Releases. Der "Check ob es ein Update gibt" passiert nicht hier,
/// sondern live über die `release_announce`-Nachricht des Noten-Servers
/// (siehe ConductorPage._handleReleaseAnnounce) – ein eigenes Pull-System
/// gegen eine update.json gibt es beim noten-server v2 nicht.
class UpdateService {
  final DownloadService _downloadService;

  UpdateService(this._downloadService);

  /// Lädt die APK für [updateInfo] herunter und liefert den lokalen
  /// Dateipfad zurück (oder null bei Fehler).
  Future<String?> downloadUpdate(
    UpdateInfo updateInfo,
    StreamController<double> progressController,
  ) async {
    try {
      final fileName = DownloadService.generateFileName(updateInfo.version);
      return await _downloadService.downloadFile(
        updateInfo.url,
        fileName,
        progressController,
      );
    } catch (e) {
      UpdateLogger.error('Error downloading update', e);
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
        UpdateLogger.warning('Retry $attempt failed, waiting ${delay.inSeconds}s');
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      }
    }
    throw Exception('Max retries exceeded');
  }
}
