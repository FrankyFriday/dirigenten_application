// lib/conductor_page.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'shared.dart';

class ConductorPage extends StatefulWidget {
  const ConductorPage({super.key});

  @override
  State<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends State<ConductorPage> {
  HttpServer? _wsServer;
  final List<WebSocket> _clients = [];
  bool _serverRunning = false;
  String _serverStatus = 'Server nicht gestartet';
  String _homeServerBaseUrl = ''; // z.B. http://meineip:8000
  List<File> _localPieces = []; // lokal gespeicherte PDFs (vom Heimserver geladen)
  final _portController = TextEditingController(text: '4040');
  final _homeUrlController = TextEditingController(); // für UI-Eingabe

  @override
  void initState() {
    super.initState();
    _loadLocalPieces();
  }

  Future<void> _loadLocalPieces() async {
    final dir = await getApplicationDocumentsDirectory();
    final list = dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.pdf')).toList();
    setState(() => _localPieces = list);
  }

  Future<void> _startWsServer() async {
    final port = int.tryParse(_portController.text) ?? 4040;
    try {
      _wsServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
      setState(() {
        _serverRunning = true;
        _serverStatus = 'Warte auf Verbindungen auf Port $port';
      });
      _wsServer!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleClient(socket);
        } else {
          // optional: einfache Health-Check Seite
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.text
            ..write('Marschpad Dirigent WebSocket-Host')
            ..close();
        }
      });
    } catch (e) {
      setState(() {
        _serverRunning = false;
        _serverStatus = 'Fehler beim Starten: $e';
      });
    }
  }

  void _handleClient(WebSocket socket) {
    _clients.add(socket);
    final addr = socket.hashCode;
    setState(() => _serverStatus = 'Client verbunden (${_clients.length})');
    socket.listen((data) {
      try {
        final map = jsonDecode(data as String);
        final type = map['type'];
        if (type == 'register') {
          // kann bei Bedarf weiterverarbeitet werden (z.B. Anzeige Instrument/Stimme)
          debugPrint('Client registriert: $map');
        }
      } catch (e) {
        debugPrint('Fehler parsing client message: $e');
      }
    }, onDone: () {
      _clients.remove(socket);
      setState(() => _serverStatus = 'Client getrennt (${_clients.length})');
    }, onError: (e) {
      _clients.remove(socket);
      setState(() => _serverStatus = 'Client-Error (${_clients.length})');
    });
  }

  Future<void> _stopWsServer() async {
    for (var c in List<WebSocket>.from(_clients)) {
      c.add(jsonEncode({'type': 'status', 'text': 'Dirigent beendet'}));
      await c.close();
    }
    _clients.clear();
    await _wsServer?.close(force: true);
    setState(() {
      _serverRunning = false;
      _serverStatus = 'Server gestoppt';
    });
  }

  Future<void> _downloadPiecesFromHome() async {
    final base = _homeUrlController.text.trim();
    if (base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Heimserver-Base-URL angeben')));
      return;
    }
    // Erwartet: GET {base}/pieces -> JSON list of filenames
    try {
      final listResp = await http.get(Uri.parse('$base/pieces'));
      if (listResp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Abrufen der Liste: ${listResp.statusCode}')));
        return;
      }
      final List<dynamic> names = jsonDecode(listResp.body);
      final dir = await getApplicationDocumentsDirectory();
      for (var name in names) {
        final url = '$base/download/${Uri.encodeComponent(name)}';
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200) {
          final file = File('${dir.path}/$name');
          await file.writeAsBytes(resp.bodyBytes, flush: true);
        }
      }
      await _loadLocalPieces();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download abgeschlossen')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  // send piece to connected clients, optionally filtered by instrument/voice
  Future<void> _sendPieceToClients(File piece, {String? instrument, String? voice}) async {
    final bytes = await piece.readAsBytes();
    final b64 = base64Encode(bytes);
    final msg = jsonEncode({
      'type': 'send_piece',
      'name': piece.uri.pathSegments.last,
      'instrument': instrument, // if null => everyone
      'voice': voice, // if null => everyone
      'data': b64,
    });
    for (var c in List<WebSocket>.from(_clients)) {
      try {
        c.add(msg);
      } catch (e) {
        debugPrint('Fehler beim Senden an Client: $e');
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gesendet: ${piece.uri.pathSegments.last}')));
  }

  @override
  void dispose() {
    _stopWsServer();
    super.dispose();
  }

  Widget _buildLocalPiecesList() {
    if (_localPieces.isEmpty) return const Text('Keine lokal gespeicherten Noten. Bitte herunterladen.');
    return ListView.builder(
      itemCount: _localPieces.length,
      itemBuilder: (context, i) {
        final f = _localPieces[i];
        return ListTile(
          title: Text(f.uri.pathSegments.last),
          subtitle: Text(f.path),
          trailing: PopupMenuButton<String>(
            onSelected: (choice) async {
              if (choice == 'send_all') {
                await _sendPieceToClients(f);
              } else if (choice == 'send_instrument') {
                // Beispiel: prompt instrument + voice
                final instrument = await _inputDialog(context, 'Instrument (z.B. Trompete)');
                final voice = await _inputDialog(context, 'Stimme (z.B. 1. Stimme)');
                if (instrument != null) await _sendPieceToClients(f, instrument: instrument, voice: voice);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'send_all', child: Text('An alle senden')),
              const PopupMenuItem(value: 'send_instrument', child: Text('An Instrument/Stimme senden')),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _inputDialog(BuildContext ctx, String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text(label),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Abbruch')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dirigent - Downloader & Host'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text('WS-Server Status: $_serverStatus'),
            Row(
              children: [
                Expanded(child: TextField(controller: _portController, decoration: const InputDecoration(labelText: 'WS Port'))),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _serverRunning ? _stopWsServer : _startWsServer,
                  child: Text(_serverRunning ? 'Stoppen' : 'Server starten'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _homeUrlController, decoration: const InputDecoration(labelText: 'Heimserver Base URL (z.B. http://meineip:8000)')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _downloadPiecesFromHome, child: const Text('Noten vom Heimserver laden')),
            const SizedBox(height: 12),
            const Text('Lokal gespeicherte Noten:'),
            Expanded(child: _buildLocalPiecesList()),
          ],
        ),
      ),
    );
  }
}
