import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import '../utils/logger.dart';
import '../utils/platform_utils.dart';

/// Service for downloading update files with progress tracking.
class DownloadService {
  final Dio _dio;

  DownloadService(this._dio);

  /// Downloads a file from the given URL to the downloads directory.
  /// Returns a stream of download progress (0.0 to 1.0).
  Future<String?> downloadFile(
    String url,
    String fileName,
    StreamController<double> progressController,
  ) async {
    try {
      UpdateLogger.info('Starting download from $url');

      final downloadPath = await PlatformUtils.getDownloadPath();
      final filePath = '$downloadPath/$fileName';

      // Ensure download directory exists
      final dir = Directory(downloadPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            progressController.add(progress);
          }
        },
      );

      UpdateLogger.info('Download completed: $filePath');
      return filePath;
    } catch (e) {
      UpdateLogger.error('Download failed', e);
      progressController.addError(e);
      return null;
    }
  }

  /// Generates a filename for the update based on version and platform.
  static String generateFileName(String version) {
    final extension = PlatformUtils.getInstallerExtension();
    return 'app-update-$version$extension';
  }
}