import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/update_info.dart';
import '../utils/logger.dart';

/// Repository for fetching update information from the server.
class UpdateRepository {
  final Dio _dio;
  final String updateUrl;

  UpdateRepository(this._dio, {required this.updateUrl});

  /// Fetches update information from the server.
  Future<UpdateInfo?> fetchUpdateInfo() async {
    try {
      UpdateLogger.info('Fetching update info from $updateUrl');
      final response = await _dio.get(updateUrl);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is String) {
          final jsonData = json.decode(data);
          return UpdateInfo.fromJson(jsonData);
        } else if (data is Map<String, dynamic>) {
          return UpdateInfo.fromJson(data);
        }
      }
      UpdateLogger.warning('Failed to fetch update info: ${response.statusCode}');
      return null;
    } catch (e) {
      UpdateLogger.error('Error fetching update info', e);
      return null;
    }
  }
}