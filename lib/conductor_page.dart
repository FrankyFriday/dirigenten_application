import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ConductorPage extends StatefulWidget {
  const ConductorPage({super.key});

  @override
  State<ConductorPage> createState() => _ConductorPageState();
}

// ================= CLIENT INFO =================
class ClientInfo {
  final WebSocket socket;
  final String instrument;
  final String voice;

  ClientInfo({
    required this.socket,
    required this.instrument,
    required this.voice,
  });
}

class _ConductorPageState extends State<ConductorPage> {
  HttpServer? _wsServer;
  final List<ClientInfo> _clients = [];

  bool _serverRunning = false;
  String _serverStatus = 'Server nicht gestartet';
  List<File> _localPieces = [];
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;

  final _portController = TextEditingController(text: '4041');
  final _homeUrlController = TextEditingController();

  bool _loadingPieces = false;

  @override
  void initState() {
    super.initState();
    _loadLocalPieces();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // ================= LADEN LOKALER STÜCKE =================
  Future<void> _loadLocalPieces() async {
    _safeSetState(() => _loadingPieces = true);

    Directory dir;

    if (kIsWeb) {
      _localPieces = [];
      _safeSetState(() => _loadingPieces = false);
      return;
    } else if (Platform.isAndroid || Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      dir = Directory(r'C:\TestNoten');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    final list = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();

    _safeSetState(() {
      _localPieces = list;
      _loadingPieces = false;
    });

    debugPrint('Gefundene Noten: ${_localPieces.map((f) => f.path).join(', ')}');
  }

  // ================= SERVER START =================
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

  // ================= CLIENT HANDLING =================
  void _handleClient(WebSocket socket) {
    socket.listen((data) {
      try {
        final map = jsonDecode(data as String);
        if (map['type'] == 'register') {
          final instrument = map['instrument'] as String? ?? '';
          final voice = map['voice'] as String? ?? '';
          _clients.add(ClientInfo(socket: socket, instrument: instrument, voice: voice));
          _safeSetState(() => _serverStatus = 'Client verbunden (${_clients.length})');
          debugPrint("Registriert: $map");
        }
      } catch (_) {}
    }, onDone: () {
      _clients.removeWhere((c) => c.socket == socket);
      _safeSetState(() => _serverStatus = 'Client getrennt (${_clients.length})');
    });
  }

  // ================= UDP BROADCAST =================
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

  // ================= SERVER STOP =================
  Future<void> _stopWsServer() async {
    for (var c in _clients) {
      try {
        c.socket.add(jsonEncode({'type': 'status', 'text': 'Dirigent beendet'}));
        await c.socket.close();
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

  Future<void> _stopWsServerWithoutSetState() async {
    for (var c in _clients) {
      try {
        c.socket.add(jsonEncode({'type': 'status', 'text': 'Dirigent beendet'}));
        await c.socket.close();
      } catch (_) {}
    }
    _clients.clear();
    await _wsServer?.close(force: true);
    _broadcastTimer?.cancel();
    _udpSocket?.close();
  }

  // ================= PIECE SENDING =================
  Future<void> _sendPiece(File f, {String? targetInstrument, String? targetVoice}) async {
    final bytes = await f.readAsBytes();
    final msg = jsonEncode({
      'type': 'send_piece',
      'name': f.uri.pathSegments.last,
      'data': base64Encode(bytes),
      'instrument': targetInstrument,
      'voice': targetVoice,
    });

    for (var client in _clients) {
      if (targetInstrument != null && targetVoice != null) {
        if (client.instrument == targetInstrument && client.voice == targetVoice) {
          client.socket.add(msg);
        }
      } else {
        client.socket.add(msg);
      }
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

  // ================= STÜCKE GRUPPIEREN =================
  List<PieceGroup> _groupLocalPieces() {
    final Map<String, List<String>> map = {};

    for (var file in _localPieces) {
      final fileName = file.uri.pathSegments.last;
      final parts = fileName.replaceAll('.pdf', '').split('_');
      if (parts.length >= 3) {
        final pieceName = parts[0];
        final instrumentVoice = "${parts[1]} ${parts[2]}";
        map.putIfAbsent(pieceName, () => []).add(instrumentVoice);
      } else {
        map.putIfAbsent(fileName.replaceAll('.pdf', ''), () => []).add("Unbekannt");
      }
    }

    return map.entries
        .map((e) => PieceGroup(name: e.key, instrumentsAndVoices: e.value))
        .toList();
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupedPieces = _groupLocalPieces();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dirigent Dashboard'),
        centerTitle: true,
        elevation: 4,
        backgroundColor: Colors.deepPurple.shade700,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Server Status
            Text(
              'Server Status',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _serverRunning ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _serverRunning ? Colors.green : Colors.red,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _serverRunning ? Icons.cloud_done : Icons.cloud_off,
                    color: _serverRunning ? Colors.green.shade700 : Colors.red.shade700,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _serverStatus,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _serverRunning ? Colors.green.shade900 : Colors.red.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Server Controls
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'WebSocket Port',
                      labelStyle: TextStyle(color: Colors.deepPurple.shade700),
                      filled: true,
                      fillColor: Colors.deepPurple.shade50.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _serverRunning ? _stopWsServer : _startWsServer,
                    icon: Icon(_serverRunning ? Icons.stop_circle : Icons.play_circle_fill, size: 26),
                    label: Text(
                      _serverRunning ? 'Stoppen' : 'Starten',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: _serverRunning ? Colors.redAccent : Colors.deepPurple.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Lokale Noten
            Text(
              'Lokale Noten',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade900,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _loadingPieces
                  ? const Center(child: CircularProgressIndicator())
                  : groupedPieces.isEmpty
                      ? Center(
                          child: Text(
                            'Keine lokalen Noten gefunden.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          itemCount: groupedPieces.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final group = groupedPieces[i];
                            return Card(
                              elevation: 5,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              color: Colors.white,
                              shadowColor: Colors.deepPurple.shade100,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                leading: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.deepPurple.shade50,
                                  child: const Icon(Icons.picture_as_pdf, color: Colors.deepPurple, size: 32),
                                ),
                                title: Text(
                                  group.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                                ),
                                subtitle: Text(
                                  group.instrumentsAndVoices.join(', '),
                                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                                ),
                                trailing: ElevatedButton.icon(
                                  onPressed: () {
                                    for (var iv in group.instrumentsAndVoices) {
                                      final parts = iv.split(' ');
                                      if (parts.length < 2) continue;
                                      final instrument = parts[0];
                                      final voice = parts[1];

                                      final fileName = "${group.name}_${instrument}_${voice}.pdf";
                                      final file = _localPieces.firstWhere(
                                        (f) => f.uri.pathSegments.last == fileName,
                                        orElse: () => File(''),
                                      );
                                      if (file.existsSync()) {
                                        _sendPiece(file, targetInstrument: instrument, targetVoice: voice);
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.send, color: Colors.white),
                                  label: const Text('Senden', style: TextStyle(color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple.shade700,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= PIECE GROUP =================
class PieceGroup {
  final String name;
  final List<String> instrumentsAndVoices;

  PieceGroup({required this.name, required this.instrumentsAndVoices});
}
