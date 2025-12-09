import 'dart:convert';
import 'dart:async';
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
  List<File> _localPieces = [];
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;

  final _portController = TextEditingController(text: '4041');
  final _homeUrlController = TextEditingController();

  bool _loadingPieces = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _loadLocalPieces();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadLocalPieces() async {
    _safeSetState(() => _loadingPieces = true);
    final dir = await getApplicationDocumentsDirectory();
    final list = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();
    _safeSetState(() {
      _localPieces = list;
      _loadingPieces = false;
    });
  }

  Future<void> _startWsServer() async {
    final port = int.tryParse(_portController.text) ?? 4040;

    try {
      _wsServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _safeSetState(() {
        _serverRunning = true;
        _serverStatus = 'Server gestartet auf Port $port';
      });

      _wsServer!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleClient(socket);
        }
      });

      _startBroadcast(port);
    } catch (e) {
      _safeSetState(() {
        _serverRunning = false;
        _serverStatus = 'Fehler beim Starten: $e';
      });
    }
  }

  void _handleClient(WebSocket socket) {
    _clients.add(socket);
    _safeSetState(() => _serverStatus = 'Client verbunden (${_clients.length})');

    socket.listen((data) {
      try {
        final map = jsonDecode(data as String);
        if (map['type'] == 'register') {
          debugPrint("Registriert: $map");
        }
      } catch (_) {}
    }, onDone: () {
      _clients.remove(socket);
      _safeSetState(() => _serverStatus = 'Client getrennt (${_clients.length})');
    });
  }

  Future<void> _startBroadcast(int port) async {
    final ip = await _getLocalIp();
    if (ip == null) return;

    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _udpSocket!.broadcastEnabled = true;

    final msg = jsonEncode({
      'type': 'conductor_discovery',
      'ip': ip,
      'port': port,
    });

    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _udpSocket!.send(
        utf8.encode(msg),
        InternetAddress("255.255.255.255"),
        4210,
      );
    });

    debugPrint("Conductor Broadcast aktiv → $msg");
  }

  Future<String?> _getLocalIp() async {
    for (var iface in await NetworkInterface.list()) {
      for (var addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback &&
            addr.address.startsWith("192.")) {
          return addr.address;
        }
      }
    }
    return null;
  }

  Future<void> _stopWsServer() async {
    for (var c in _clients) {
      try {
        c.add(jsonEncode({'type': 'status', 'text': 'Dirigent beendet'}));
        await c.close();
      } catch (_) {}
    }
    _clients.clear();

    await _wsServer?.close(force: true);

    _broadcastTimer?.cancel();
    _udpSocket?.close();

    _safeSetState(() {
      _serverRunning = false;
      _serverStatus = 'Server gestoppt';
    });
  }

  // Extra Methode für dispose, wo kein setState() mehr aufgerufen wird
  Future<void> _stopWsServerWithoutSetState() async {
    for (var c in _clients) {
      try {
        c.add(jsonEncode({'type': 'status', 'text': 'Dirigent beendet'}));
        await c.close();
      } catch (_) {}
    }
    _clients.clear();

    await _wsServer?.close(force: true);

    _broadcastTimer?.cancel();
    _udpSocket?.close();
  }

  Future<void> _downloadPiecesFromHome() async {
    final base = _homeUrlController.text.trim();
    if (base.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bitte Heimserver-URL eingeben')));
      return;
    }

    _safeSetState(() {
      _downloading = true;
    });

    try {
      final listResp = await http.get(Uri.parse('$base/pieces'));
      if (listResp.statusCode != 200) {
        throw 'Fehler beim Abrufen der Liste';
      }

      final List names = jsonDecode(listResp.body);
      final dir = await getApplicationDocumentsDirectory();

      for (var name in names) {
        final resp = await http.get(Uri.parse('$base/download/$name'));
        if (resp.statusCode == 200) {
          final file = File('${dir.path}/$name');
          await file.writeAsBytes(resp.bodyBytes);
        }
      }

      await _loadLocalPieces();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Download abgeschlossen')));

    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      _safeSetState(() {
        _downloading = false;
      });
    }
  }

  Future<void> _sendPiece(File f) async {
    final bytes = await f.readAsBytes();
    final msg = jsonEncode({
      'type': 'send_piece',
      'name': f.uri.pathSegments.last,
      'data': base64Encode(bytes),
      'instrument': null,
      'voice': null,
    });

    for (var c in _clients) {
      try {
        c.add(msg);
      } catch (_) {}
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Noten gesendet: ${f.uri.pathSegments.last}')),
    );
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    _udpSocket?.close();

    _stopWsServerWithoutSetState();

    _portController.dispose();
    _homeUrlController.dispose();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);

  return Scaffold(
    appBar: AppBar(
      title: const Text('Dirigent'),
      centerTitle: true,
      backgroundColor: theme.colorScheme.primary,
      elevation: 4,
    ),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Status:',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: _serverRunning ? Colors.green.shade100 : Colors.red.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _serverStatus,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _serverRunning ? Colors.green.shade800 : Colors.red.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Port + Start/Stop Button
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'WebSocket Port',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _serverRunning ? _stopWsServer : _startWsServer,
                  icon: Icon(_serverRunning ? Icons.stop_circle : Icons.play_circle_fill, size: 28),
                  label: Text(_serverRunning ? 'Stoppen' : 'Starten', style: const TextStyle(fontSize: 18)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: _serverRunning ? Colors.red : theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Heimserver URL
          TextField(
            controller: _homeUrlController,
            decoration: InputDecoration(
              labelText: 'Heimserver URL',
              hintText: 'https://example.com',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              prefixIcon: const Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),

          // Download Button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              icon: _downloading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download, size: 24),
              label: const Text(
                'Noten laden',
                style: TextStyle(fontSize: 18),
              ),
              onPressed: _downloading ? null : _downloadPiecesFromHome,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Lokale Noten Header
          Text(
            'Lokale Noten',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Noten Liste
          Expanded(
            child: _loadingPieces
                ? const Center(child: CircularProgressIndicator())
                : _localPieces.isEmpty
                    ? Center(
                        child: Text(
                          'Keine lokalen Noten gefunden.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _localPieces.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final file = _localPieces[i];
                          final fileName = file.uri.pathSegments.last;

                          return Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              leading: CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.deepPurple.shade100,
                                child: const Icon(Icons.picture_as_pdf, color: Colors.deepPurple, size: 32),
                              ),
                              title: Text(
                                fileName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.send, color: Colors.deepPurple),
                                tooltip: 'Noten senden',
                                onPressed: () => _sendPiece(file),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    )
    );
  }
}

