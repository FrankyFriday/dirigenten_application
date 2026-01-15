import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/piece_group.dart';
import '../services/nextcloud_service.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

class ConductorPage extends StatefulWidget {
  const ConductorPage({super.key});

  @override
  State<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends State<ConductorPage> {
  final NextcloudService _service = NextcloudService();
  WebSocketChannel? _channel;
  late final String _clientId;
  List<PieceGroup> _pieces = [];
  PieceGroup? _currentPiece;
  String _status = 'Nicht verbunden';
  bool _loading = true;

  static const double _radius = 20.0;

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    _loadPieces();
  }

  Future<void> _loadPieces() async {
    setState(() => _loading = true);
    try {
      _pieces = await _service.loadPieces();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden der Liste: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    const domain = 'ws.notenserver.duckdns.org';
    setState(() => _status = 'Verbinde…');
    try {
      final socket = await WebSocket.connect('wss://$domain');
      final channel = IOWebSocketChannel(socket);

      channel.sink.add(jsonEncode({
        'type': 'register',
        'clientId': _clientId,
        'role': 'conductor',
      }));

      channel.stream.listen((msg) {
        try {
          final map = jsonDecode(msg as String);
          if (map['type'] == 'status') setState(() => _status = map['text']);
        } catch (_) {}
      });

      setState(() {
        _channel = channel;
        _status = 'Verbunden';
      });
    } catch (e) {
      setState(() => _status = 'Fehler: $e');
    }
  }

  void _sendPiece(PieceGroup group) {
    if (_channel == null) return;

    setState(() => _currentPiece = group);

    for (var instrument in group.instrumentsAndVoices) {
      final msg = jsonEncode({
        'type': 'send_piece_signal',
        'name': group.name,
        'instrument': instrument,
      });
      _channel!.sink.add(msg);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🎵 Stück gesendet: ${group.name}')),
    );
  }

  void _endPiece() {
    if (_channel == null || _currentPiece == null) return;

    _channel!.sink.add(jsonEncode({
      'type': 'end_piece_signal',
      'name': _currentPiece!.name,
    }));

    setState(() => _currentPiece = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🛑 Stück beendet')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Dirigent Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        elevation: 6,
        shadowColor: Colors.deepPurple.shade300,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ================= Statusbar =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Status: $_status',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _channel == null ? _connect : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: const Text('Verbinden'),
                    ),
                  ],
                ),
              ),
            ),

            // ================= Stückeliste =================
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _pieces.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final group = _pieces[i];
                        final isCurrent = _currentPiece == group;

                        return Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(_radius),
                          ),
                          shadowColor: Colors.deepPurple.shade100,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Titel
                                Text(
                                  group.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: isCurrent ? Colors.deepPurple : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // Instrumente als einfache Textzeilen
                                ...group.instrumentsAndVoices.map((ins) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Text(
                                        ins,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    )),
                                const SizedBox(height: 12),
                                // Senden Button
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _sendPiece(group),
                                    icon: const Icon(Icons.send, size: 20),
                                    label: const Text('Senden'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.deepPurple.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // ================= Stück zu Ende =================
            if (_currentPiece != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: _endPiece,
                  icon: const Icon(Icons.stop_circle, size: 22),
                  label: const Text(
                    'Stück zu Ende',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_radius),
                    ),
                    elevation: 6,
                  ),
                ),
              ),
          ],
        ),
      ), 
    );
  }
}
