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
        SnackBar(content: Text('Fehler beim Laden: $e')),
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
        final map = jsonDecode(msg as String);
        if (map['type'] == 'status') {
          setState(() => _status = map['text']);
        }
      });

      setState(() {
        _channel = channel;
        _status = 'Verbunden';
      });
    } catch (e) {
      setState(() => _status = 'Fehler');
    }
  }

  void _sendPiece(PieceGroup group) {
    if (_channel == null) return;

    setState(() => _currentPiece = group);

    for (var iv in group.instrumentsAndVoices) {
      final parts = iv.split(' ');
      if (parts.length < 2) continue;

      _channel!.sink.add(jsonEncode({
        'type': 'send_piece_signal',
        'name': group.name,
        'instrument': parts[0],
        'voice': parts[1],
      }));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stück gesendet: ${group.name}')),
    );
  }

  void _endPiece() {
    if (_channel == null || _currentPiece == null) return;

    _channel!.sink.add(jsonEncode({
      'type': 'end_piece_signal',
      'name': _currentPiece!.name,
    }));

    setState(() => _currentPiece = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: const Text(
          'Dirigentenpult',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _StatusHeader(
            status: _status,
            onConnect: _channel == null ? _connect : null,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: _pieces.length,
                    itemBuilder: (_, i) {
                      final group = _pieces[i];
                      final isActive = _currentPiece == group;
                      return _PieceCard(
                        group: group,
                        active: isActive,
                        onSend: () => _sendPiece(group),
                      );
                    },
                  ),
          ),
          if (_currentPiece != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton.icon(
                onPressed: _endPiece,
                icon: const Icon(Icons.stop),
                label: const Text(
                  'Stück beenden',
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ===================== STATUS HEADER ===================== */

class _StatusHeader extends StatelessWidget {
  final String status;
  final VoidCallback? onConnect;

  const _StatusHeader({
    required this.status,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final connected = status.toLowerCase().contains('verbunden');

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.wifi : Icons.wifi_off,
            color: connected ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: onConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Verbinden'),
          ),
        ],
      ),
    );
  }
}

/* ===================== PIECE CARD ===================== */

class _PieceCard extends StatelessWidget {
  final PieceGroup group;
  final bool active;
  final VoidCallback onSend;

  const _PieceCard({
    required this.group,
    required this.active,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
        border: active
            ? Border.all(color: Colors.deepPurpleAccent, width: 2)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: active ? Colors.deepPurpleAccent : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.instrumentsAndVoices.join(', '),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Senden'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
