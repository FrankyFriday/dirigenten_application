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

  /// Liest nur die PDF-Dateien und erstellt daraus die Stückliste
  /// Gruppiert nur nach Instrument, nicht nach Stimme
  Future<List<PieceGroup>> loadPieces() async {
    final uri = Uri.parse('$baseUrl/');
    final request = await HttpClient().openUrl('PROPFIND', uri);
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader());
    request.headers.set('Depth', '1'); // 🔹 nur eine Ebene laden → schneller
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    // Alle PDFs finden
    final regex = RegExp(r'<d:href>([^<]+\.pdf)</d:href>');
    final filenames = regex.allMatches(body).map((m) {
      final fullPath = Uri.decodeFull(m.group(1)!);
      final segments = fullPath.split('/');
      return segments.isNotEmpty ? segments.last : fullPath;
    }).toList();

    // Map: Stückname -> Set<Instrument>
    final Map<String, Set<String>> map = {};

    for (var fileName in filenames) {
      final parts = fileName.replaceAll('.pdf', '').split('_');
      if (parts.length >= 3) {
        final pieceName = parts[0];
        final instrument = parts[1]; // nur Instrument
        map.putIfAbsent(pieceName, () => {}).add(instrument);
      } else {
        map.putIfAbsent(fileName.replaceAll('.pdf', ''), () => {}).add("Unbekannt");
      }
    }

    // Map in PieceGroup Liste umwandeln
    return map.entries
        .map((e) => PieceGroup(
              name: e.key,
              instrumentsAndVoices: e.value.toList(), // nur Instrumente
            ))
        .toList();
  }
}
