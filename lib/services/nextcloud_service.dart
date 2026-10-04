import 'dart:convert';
import 'dart:io';
import '../models/piece_group.dart';
import '../utils/logger.dart';
import '../config/app_config.dart';

class NextcloudService {
  Uri _apiUri([String? relativePath]) {
    final path = relativePath == null || relativePath.isEmpty
        ? '/api/notes'
        : '/api/notes/$relativePath';
    return Uri.https(AppConfig.wsDomain, path);
  }

  Future<List<String>> _loadAllPdfPaths() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(_apiUri());
      final response = await request.close().timeout(
            const Duration(seconds: 30),
          );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Notenserver antwortete mit HTTP ${response.statusCode}.',
          uri: _apiUri(),
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['files'] is! List) {
        throw const FormatException('Ungültige Notenliste vom Notenserver.');
      }

      return (decoded['files'] as List)
          .whereType<String>()
          .where((path) => path.toLowerCase().endsWith('.pdf'))
          .toList();
    } catch (error, stackTrace) {
      UpdateLogger.error(
        'Fehler beim Laden der Stücke vom Notenserver.',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// Erstellt die Stückliste aus den PDF-Dateinamen
  Future<List<PieceGroup>> loadPieces() async {
    final paths = await _loadAllPdfPaths();

    // Map: Stückname -> Instrument + Stimme
    final Map<String, List<String>> map = {};
    for (final fullPath in paths) {
      final fileName = fullPath.split('/').last;
      final clean = fileName.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final parts = clean.split('_');

      // Erwartetes Schema: Stück_Instrument_Stimme.pdf
      if (parts.length >= 3) {
        final pieceName = parts[0];
        final instrument = parts[1];
        final voice = parts[2];

        map.putIfAbsent(pieceName, () => []).add('$instrument $voice');
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
