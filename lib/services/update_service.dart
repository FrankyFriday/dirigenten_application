import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class UpdateService {
  final String owner;
  final String repo;

  UpdateService({required this.owner, required this.repo});

  factory UpdateService.fromEnv({required String repoKey}) {
    final owner = dotenv.env['GITHUB_OWNER']!;
    final repo = dotenv.env[repoKey]!;
    return UpdateService(owner: owner, repo: repo);
  }

  Future<String?> getLatestVersion() async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
      final resp = await http.get(url);
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      return data['tag_name'] as String?;
    } catch (e) {
      debugPrint('UpdateService Error: $e');
      return null;
    }
  }

  Future<String?> getLatestApkUrl() async {
    try {
      final url = Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');
      final resp = await http.get(url);
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body);
      final assets = data['assets'] as List;
      final apk = assets.firstWhere(
        (a) => a['name'].toString().endsWith('.apk'),
        orElse: () => null,
      );
      return apk?['browser_download_url'] as String?;
    } catch (e) {
      debugPrint('UpdateService APK Error: $e');
      return null;
    }
  }
}
