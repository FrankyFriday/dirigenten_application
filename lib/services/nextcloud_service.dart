import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/piece_group.dart';
import '../utils/logger.dart';

class NextcloudService {
  final String baseUrl = dotenv.env['NEXTCLOUD_BASE_URL'] ?? '';
  final String username = dotenv.env['NEXTCLOUD_USER'] ?? '';
  final String password = dotenv.env['NEXTCLOUD_PASSWORD'] ?? '';

  String _authHeader() {
    if (username.isEmpty || password.isEmpty) {
      throw StateError('Nextcloud-Zugangsdaten fehlen.');
    }

    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  Uri _baseUri() {
    final value = baseUrl.trim();
    if (value.isEmpty) {
      throw StateError('NEXTCLOUD_BASE_URL ist nicht gesetzt.');
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('Ungültige Nextcloud-Server-URL: $value');
    }

    return uri;
  }

  Uri _validatedUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('Ungültige HTTP-URL: $value');
    }
    return uri;
  }

  Uri _resolveHref(String href) {
    final base = _baseUri();
    final decodedHref = Uri.decodeFull(href.trim());
    final parsedHref = Uri.tryParse(decodedHref);

    if (parsedHref == null) {
      throw FormatException('Ungültiger WebDAV-Pfad: $href');
    }

    final resolved = parsedHref.hasScheme
        ? parsedHref
        : decodedHref.startsWith('/')
            ? base.replace(
                path: parsedHref.path,
                query: parsedHref.query,
                fragment: parsedHref.fragment,
              )
            : base.resolve(decodedHref);

    return _validatedUri(resolved.toString());
  }

  /// Lädt alle PDF-Dateipfade rekursiv
  Future<List<String>> _loadAllPdfPaths() async {
    final base = _baseUri();
    final requestUri = _validatedUri(
      base
          .replace(
            path: base.path.endsWith('/') ? base.path : '${base.path}/',
          )
          .toString(),
    );
    UpdateLogger.info('Nextcloud-Basis-URL: ${_safeUri(base)}');
    UpdateLogger.info('WebDAV-PROPFIND: ${_safeUri(requestUri)}');

    final client = HttpClient();
    try {
      final request = await client.openUrl('PROPFIND', requestUri);
      request.headers.set(HttpHeaders.authorizationHeader, _authHeader());
      request.headers.set('Depth', 'infinity');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      UpdateLogger.info('Nextcloud HTTP-Status: ${response.statusCode}');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Nextcloud antwortete mit HTTP ${response.statusCode}.',
          uri: requestUri,
        );
      }

      final regex = RegExp(r'<d:href>([^<]+\.pdf)</d:href>');
      return regex
          .allMatches(body)
          .map((match) => _resolveHref(match.group(1)!))
          .map((uri) => uri.toString())
          .toList();
    } catch (error, stackTrace) {
      UpdateLogger.error(
        'Fehler beim Laden der Stücke von Nextcloud.',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  String _safeUri(Uri uri) => uri.replace(userInfo: '').toString();

  /// Erstellt die Stückliste aus den PDF-Dateinamen
  Future<List<PieceGroup>> loadPieces() async {
    final paths = await _loadAllPdfPaths();

    // Map: Stückname -> Instrument + Stimme
    final Map<String, List<String>> map = {};

    for (final fullPath in paths) {
      final fileUri = Uri.parse(fullPath);
      final fileName = fileUri.pathSegments.last;
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
