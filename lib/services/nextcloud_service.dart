import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/piece_group.dart';

class NextcloudService {
  final String baseUrl = dotenv.env['NEXTCLOUD_BASE_URL'] ?? '';
  final String username = dotenv.env['NEXTCLOUD_USER'] ?? '';
  final String password = dotenv.env['NEXTCLOUD_PASSWORD'] ?? '';

  String _authHeader() =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /// Lädt alle PDF-Dateipfade rekursiv
  Future<List<String>> _loadAllPdfPaths() async {
    final uri = Uri.parse('$baseUrl/');
    final request = await HttpClient().openUrl('PROPFIND', uri);
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader());
    request.headers.set('Depth', 'infinity');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    final regex = RegExp(r'<d:href>([^<]+\.pdf)</d:href>');
    return regex
        .allMatches(body)
        .map((m) => Uri.decodeFull(m.group(1)!))
        .toList();
  }

  /// Erstellt die Stückliste aus den PDF-Dateinamen
  Future<List<PieceGroup>> loadPieces() async {
    final paths = await _loadAllPdfPaths();

    // Map: Stückname -> Instrument + Stimme
    final Map<String, List<String>> map = {};

    for (final fullPath in paths) {
      final fileName = fullPath.split('/').last;
      final clean = fileName.replaceAll('.pdf', '');
      final parts = clean.split('_');

      // Erwartetes Schema: Stück_Instrument_Stimme.pdf
      if (parts.length >= 3) {
        final pieceName = parts[0];
        final instrument = parts[1];
        final voice = parts[2];

        map
            .putIfAbsent(pieceName, () => [])
            .add('$instrument $voice');
      } else {
        // Fallback – sollte praktisch nie passieren
        map.putIfAbsent(clean, () => []).add('Unbekannt');
      }
    }

    return map.entries
        .map(
          (e) => PieceGroup(
            name: e.key,
            instrumentsAndVoices: e.value,
          ),
        )
        .toList();
  }
}
