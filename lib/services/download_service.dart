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
      throw const FormatException('Leere Download-URL.');
    }

    final parsed = Uri.tryParse(raw);

    if (parsed == null) {
      throw FormatException(
        'Ungültige Download-URL: $value',
      );
    }

    // Absolute URL
    if (parsed.hasScheme) {
      if (!parsed.hasAuthority ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        throw FormatException(
          'Ungültige Download-URL: $value',
        );
      }

      return parsed;
    }

    // Relative URL -> Nextcloud Base URL
    final baseValue =
        dotenv.env['NEXTCLOUD_BASE_URL']?.trim() ?? '';

    if (baseValue.isEmpty) {
      throw StateError(
        'NEXTCLOUD_BASE_URL fehlt in der .env.',
      );
    }

    final base = Uri.tryParse(baseValue);

    if (base == null ||
        !base.hasScheme ||
        !base.hasAuthority ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw StateError(
        'NEXTCLOUD_BASE_URL ist ungültig: $baseValue',
      );
    }

    final resolved = raw.startsWith('/')
        ? base.replace(
            path: parsed.path,
            query: parsed.query,
            fragment: parsed.fragment,
          )
        : base.resolve(raw);

    if (!resolved.hasScheme ||
        !resolved.hasAuthority ||
        (resolved.scheme != 'http' &&
            resolved.scheme != 'https')) {
      throw FormatException(
        'Ungültige aufgelöste Download-URL: $value',
      );
    }

    return resolved;
  }

  String _safeUri(Uri uri) {
    return uri.replace(userInfo: '').toString();
  }

  Future<String?> downloadFile(
    String url,
    String fileName,
    StreamController<double> progressController,
  ) async {
    try {
      UpdateLogger.info('========================================');
      UpdateLogger.info('UPDATE DOWNLOAD START');
      UpdateLogger.info('Original URL: $url');
      UpdateLogger.info('Filename: $fileName');

      // ------------------------------------------------------------
      // URL
      // ------------------------------------------------------------

      final downloadUri = _resolveDownloadUri(url);

      UpdateLogger.info(
        'Resolved URL: ${_safeUri(downloadUri)}',
      );

      // ------------------------------------------------------------
      // STORAGE
      // ------------------------------------------------------------

      final directory = await getExternalStorageDirectory();

      if (directory == null) {
        UpdateLogger.error(
          'getExternalStorageDirectory() returned null.',
        );

        progressController.addError(
          Exception(
            'Kein Speicherverzeichnis verfügbar.',
          ),
        );

        return null;
      }

      final downloadDirectory = Directory(directory.path);

      if (!await downloadDirectory.exists()) {
        await downloadDirectory.create(
          recursive: true,
        );
      }

      final filePath =
          '${downloadDirectory.path}/$fileName';

      UpdateLogger.info(
        'Download directory: ${downloadDirectory.path}',
      );

      UpdateLogger.info(
        'Target file: $filePath',
      );

      // ------------------------------------------------------------
      // NEXTCLOUD LOGIN
      // ------------------------------------------------------------

      final username =
          dotenv.env['NC_USER']?.trim() ?? '';

      final password =
          dotenv.env['NC_PASS'] ?? '';

      if (username.isEmpty) {
        throw StateError(
          'NEXTCLOUD_USER fehlt in der .env.',
        );
      }

      if (password.isEmpty) {
        throw StateError(
          'NEXTCLOUD_PASSWORD fehlt in der .env.',
        );
      }

      UpdateLogger.info(
        'Nextcloud username configured: true',
      );

      UpdateLogger.info(
        'Nextcloud password configured: true',
      );

      // ------------------------------------------------------------
      // AUTH
      // ------------------------------------------------------------

      final credentials =
          base64Encode(
        utf8.encode('$username:$password'),
      );

      // ------------------------------------------------------------
      // DOWNLOAD
      // ------------------------------------------------------------

      UpdateLogger.info(
        'Starting HTTP download...',
      );

      final response = await _dio.download(
        downloadUri.toString(),
        filePath,
        options: Options(
          headers: {
            'Authorization': 'Basic $credentials',
            'Accept': '*/*',
            'User-Agent': 'DirigentenApp/1.0',
          },

          // Dio darf nur echte 2xx Antworten akzeptieren.
          validateStatus: (status) {
            return status != null &&
                status >= 200 &&
                status < 300;
          },

          // Wichtig bei großen APKs
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 2),
        ),

        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress =
                received / total;

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

      UpdateLogger.info(
        'Dio download finished.',
      );

      UpdateLogger.info(
        'Response status: ${response.statusCode}',
      );

      // ------------------------------------------------------------
      // FILE CHECK
      // ------------------------------------------------------------

      final downloadedFile =
          File(filePath);

      if (!await downloadedFile.exists()) {
        UpdateLogger.error(
          'Download finished but file does not exist.',
        );

        progressController.addError(
          Exception(
            'Download abgeschlossen, Datei wurde aber nicht gefunden.',
          ),
        );

        return null;
      }

      final size =
          await downloadedFile.length();

      if (size <= 0) {
        UpdateLogger.error(
          'Downloaded file is empty.',
        );

        await downloadedFile.delete();

        progressController.addError(
          Exception(
            'Die heruntergeladene Datei ist leer.',
          ),
        );

        return null;
      }

      // Download abgeschlossen
      progressController.add(1.0);

      UpdateLogger.info(
        'Download completed successfully.',
      );

      UpdateLogger.info(
        'File size: $size bytes',
      );

      UpdateLogger.info(
        'File path: $filePath',
      );

      UpdateLogger.info(
        'UPDATE DOWNLOAD END',
      );

      UpdateLogger.info(
        '========================================',
      );

      return filePath;
    }

    // --------------------------------------------------------------
    // DIO ERROR
    // --------------------------------------------------------------

    on DioException catch (e) {
      UpdateLogger.error(
        '========================================',
      );

      UpdateLogger.error(
        'UPDATE DOWNLOAD FAILED',
      );

      UpdateLogger.error(
        'Dio error type: ${e.type}',
      );

      UpdateLogger.error(
        'Dio message: ${e.message}',
      );

      UpdateLogger.error(
        'Dio error: ${e.error}',
      );

      if (e.requestOptions.uri != null) {
        UpdateLogger.error(
          'Request URL: ${_safeUri(e.requestOptions.uri)}',
        );
      }

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

        if (e.response?.data != null) {
          final data =
              e.response?.data.toString() ?? '';

          UpdateLogger.error(
            'Response body: ${data.length > 1000 ? data.substring(0, 1000) : data}',
          );
        }
      }

      switch (e.response?.statusCode) {
        case 401:
          UpdateLogger.error(
            'HTTP 401: Nextcloud authentication failed.',
          );
          break;

        case 403:
          UpdateLogger.error(
            'HTTP 403: Access forbidden.',
          );
          break;

        case 404:
          UpdateLogger.error(
            'HTTP 404: File not found.',
          );
          break;

        case 500:
          UpdateLogger.error(
            'HTTP 500: Nextcloud server error.',
          );
          break;

        case 502:
          UpdateLogger.error(
            'HTTP 502: Bad Gateway.',
          );
          break;

        case 503:
          UpdateLogger.error(
            'HTTP 503: Nextcloud unavailable.',
          );
          break;
      }

      UpdateLogger.error(
        '========================================',
      );

      progressController.addError(e);

      return null;
    }

    // --------------------------------------------------------------
    // OTHER ERROR
    // --------------------------------------------------------------

    catch (e, stackTrace) {
      UpdateLogger.error(
        '========================================',
      );

      UpdateLogger.error(
        'UNEXPECTED DOWNLOAD ERROR',
      );

      UpdateLogger.error(
        'Error: $e',
      );

      UpdateLogger.error(
        'StackTrace: $stackTrace',
      );

      UpdateLogger.error(
        '========================================',
      );

      progressController.addError(e);

      return null;
    }
  }

  static String generateFileName(
    String version,
  ) {
    final extension =
        PlatformUtils.getInstallerExtension();

    return 'app-update-$version$extension';
  }
}
