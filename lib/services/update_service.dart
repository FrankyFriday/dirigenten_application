import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

class UpdateService {
  static Future<void> downloadAndInstall(String url) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/update.apk');

      final username = dotenv.env['NEXTCLOUD_USER'] ?? '';
      final password = dotenv.env['NEXTCLOUD_PASSWORD'] ?? '';

      final headers = {
        'Authorization': 'Basic ' + base64Encode(utf8.encode('$username:$password')),
      };

      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode != 200) {
        throw Exception('Download fehlgeschlagen: ${res.statusCode}');
      }

      await file.writeAsBytes(res.bodyBytes);
      print('[UPDATE] APK heruntergeladen: ${file.path}');

      await OpenFilex.open(file.path);
    } catch (e) {
      print('[UPDATE] Fehler beim Download/Install: $e');
    }
  }
}
