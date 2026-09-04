import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';
import '../utils/platform_utils.dart';

class DownloadService {
  final Dio _dio;

  DownloadService(this._dio);

  Uri _resolveDownloadUri(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw FormatException('Leere Download-URL.');
    }

    final parsed = Uri.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Ungültige Download-URL: $value');
    }

    if (parsed.hasScheme) {
      if (!parsed.hasAuthority ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        throw FormatException('Ungültige Download-URL: $value');
      }
      return parsed;
    }

    final baseValue = dotenv.env['NEXTCLOUD_BASE_URL']?.trim() ?? '';
    final base = Uri.tryParse(baseValue);
    if (base == null ||
        !base.hasScheme ||
        !base.hasAuthority ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw StateError(
        'Relative Download-URL erhalten, aber NEXTCLOUD_BASE_URL ist ungültig.',
      );
    }

    final resolved = raw.startsWith('/')
        ? base.replace(
            path: parsed.path,
            query: parsed.query,
            fragment: parsed.fragment,
          )
        : base.resolve(raw);
    if (!resolved.hasScheme || !resolved.hasAuthority) {
      throw FormatException('Ungültige aufgelöste Download-URL: $value');
    }
    return resolved;
  }

  String _safeUri(Uri uri) => uri.replace(userInfo: '').toString();

  Future<String?> downloadFile(
    String url,
    String fileName,
    StreamController<double> progressController,
  ) async {
    try {
      final downloadUri = _resolveDownloadUri(url);
      UpdateLogger.info('========================================');
      UpdateLogger.info('UPDATE DOWNLOAD START');
      UpdateLogger.info('Download-URL: ${_safeUri(downloadUri)}');
      UpdateLogger.info('Filename: $fileName');

      // App-eigenes Verzeichnis verwenden.
      // Kein direkter Zugriff auf /storage/emulated/0/Download nötig.
      final directory = await getExternalStorageDirectory();

      if (directory == null) {
        UpdateLogger.error(
          'Kein externes App-Speicherverzeichnis verfügbar.',
        );
        return null;
      }

      final downloadPath = directory.path;
      final filePath = '$downloadPath/$fileName';

      UpdateLogger.info('Download directory: $downloadPath');
      UpdateLogger.info('Target file: $filePath');

      final dir = Directory(downloadPath);

      if (!await dir.exists()) {
        UpdateLogger.info('Creating download directory...');
        await dir.create(recursive: true);
      }

      final username = dotenv.env['NEXTCLOUD_USER'] ?? '';
      final password = dotenv.env['NEXTCLOUD_PASSWORD'] ?? '';
      if (username.isEmpty || password.isEmpty) {
        throw StateError('Nextcloud-Zugangsdaten fehlen.');
      }

      final auth = base64Encode(
        utf8.encode('$username:$password'),
      );

      UpdateLogger.info('Starting authenticated download...');

      await _dio.download(
        downloadUri.toString(),
        filePath,
        options: Options(
          headers: {
            'Authorization': 'Basic $auth',
          },
          validateStatus: (status) {
            return status != null && status >= 200 && status < 300;
          },
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;

            progressController.add(progress);

            UpdateLogger.info(
              'Download: '
              '${(progress * 100).toStringAsFixed(1)}% '
              '($received / $total bytes)',
            );
          } else {
            UpdateLogger.info(
              'Download received: $received bytes',
            );
          }
        },
      );

      final downloadedFile = File(filePath);

      if (await downloadedFile.exists()) {
        final size = await downloadedFile.length();

        UpdateLogger.info(
          'Download completed successfully.',
        );

        UpdateLogger.info(
          'File size: $size bytes',
        );

        UpdateLogger.info(
          'File path: $filePath',
        );

        UpdateLogger.info('UPDATE DOWNLOAD END');
        UpdateLogger.info('========================================');

        return filePath;
      }

      UpdateLogger.error(
        'Download reported success, but file does not exist!',
      );

      return null;
    } on DioException catch (e) {
      UpdateLogger.error('========================================');
      UpdateLogger.error('UPDATE DOWNLOAD FAILED');

      UpdateLogger.error(
        'Dio error type: ${e.type}',
      );

      UpdateLogger.error(
        'Message: ${e.message}',
      );

      if (e.response != null) {
        UpdateLogger.error(
          'HTTP status: ${e.response?.statusCode}',
        );

        UpdateLogger.error(
          'HTTP status message: ${e.response?.statusMessage}',
        );

        UpdateLogger.error(
          'Response headers: ${e.response?.headers}',
        );
      }

      if (e.response?.statusCode == 401) {
        UpdateLogger.error(
          'HTTP 401: Nextcloud rejected the credentials.',
        );
      }

      if (e.response?.statusCode == 403) {
        UpdateLogger.error(
          'HTTP 403: Access to this file is forbidden.',
        );
      }

      if (e.response?.statusCode == 404) {
        UpdateLogger.error(
          'HTTP 404: File was not found.',
        );
      }

      UpdateLogger.error('========================================');

      progressController.addError(e);

      return null;
    } catch (e) {
      UpdateLogger.error(
        'Unexpected download error: $e',
      );

      progressController.addError(e);

      return null;
    }
  }

  static String generateFileName(String version) {
    final extension = PlatformUtils.getInstallerExtension();
    return 'app-update-$version$extension';
  }
}
