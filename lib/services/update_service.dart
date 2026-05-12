import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/update_info.dart';
import '../repositories/update_repository.dart';
import '../services/version_checker.dart';
import '../services/download_service.dart';
import '../utils/logger.dart';

/// Main service for handling app updates.
/// Coordinates version checking, downloading, and installation.
class UpdateService {
  final UpdateRepository _repository;
  final DownloadService _downloadService;

  UpdateService(this._repository, this._downloadService);

  /// Checks for available updates.
  /// Returns UpdateInfo if a newer version is available, null otherwise.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      UpdateLogger.info('Checking for updates...');

      final updateInfo = await _repository.fetchUpdateInfo();
      if (updateInfo == null) {
        UpdateLogger.info('No update info available');
        return null;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      UpdateLogger.info('Current version: $currentVersion, Latest version: ${updateInfo.version}');

      if (VersionChecker.isNewerVersion(currentVersion, updateInfo.version)) {
        UpdateLogger.info('New version available');
        return updateInfo;
      } else {
        UpdateLogger.info('App is up to date');
        return null;
      }
    } catch (e) {
      UpdateLogger.error('Error checking for updates', e);
      return null;
    }
  }

  /// Downloads the update file and returns the file path.
  /// Provides progress updates via the stream controller.
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
