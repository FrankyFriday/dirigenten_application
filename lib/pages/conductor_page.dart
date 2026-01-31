import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/piece_group.dart';
import '../services/nextcloud_service.dart';
import '../services/conductor_socket.dart';
import '../services/update_service.dart';
import '../services/ui_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ConductorPage extends StatefulWidget {
  const ConductorPage({super.key});

  @override
  State<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends State<ConductorPage> {
  final NextcloudService _service = NextcloudService();
  late final ConductorSocket _socket;
  late final String _clientId;

  List<PieceGroup> _pieces = [];
  List<PieceGroup> _filteredPieces = [];
  PieceGroup? _currentPiece;
  String _status = 'Nicht verbunden';
  bool _loading = true;
  String _searchQuery = '';

  Timer? _pingTimer;
  Timer? _pongTimeoutTimer;
  final Duration _pingInterval = const Duration(seconds: 10);
  final Duration _pongTimeout = const Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    _socket = ConductorSocket(
      clientId: _clientId,
      onStatusUpdate: (s) {
        if (!mounted) return;
        setState(() => _status = s);
      },
      onMessage: _handleWSMessage,
    );
    _loadPieces();
    _socket.connect();
    _startPing();
  }

  Future<void> _loadPieces() async {
    setState(() => _loading = true);
    try {
      _pieces = await _service.loadPieces();
      _filteredPieces = List.from(_pieces);
    } catch (e) {
      if (!mounted) return;
      UIUtils.showSnackbar(context, 'Fehler beim Laden: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _handleWSMessage(Map<String, dynamic> msg) async {
    final type = msg['type'];
    if (!mounted) return;

    switch (type) {
      case 'status':
        setState(() => _status = msg['text']);
        break;
      case 'release_announce':
        final info = await PackageInfo.fromPlatform();
        String normalizeVersion(String v) => v.split('+')[0];
        final currentVersion = normalizeVersion(info.version);
        final serverVersion = normalizeVersion(msg['version']);
        if (msg['app'] == 'dirigenten_application' &&
            serverVersion != currentVersion) {
          print('[UPDATE] Neue Version gefunden: $serverVersion');
          await UpdateService.downloadAndInstall(msg['apkUrl']);
        } else {
          print('[UPDATE] Keine neue Version. Aktuell: $currentVersion');
        }
        break;
      case 'ping':
        _socket.send({'type': 'pong'});
        break;
      case 'pong':
        _resetPongTimeout();
        break;
      case 'send_piece_signal':
      case 'end_piece_signal':
        print('[WS] Server-Signal empfangen: $type');
        break;
      default:
        print('[WS] Unbekannter Typ: $type');
    }
  }

  void _sendPiece(PieceGroup group) {
    if (!_socket.isConnected) return;
    setState(() => _currentPiece = group);
    for (var iv in group.instrumentsAndVoices) {
      final parts = iv.split(' ');
      if (parts.length < 2) continue;
      _socket.send({
        'type': 'send_piece_signal',
        'name': group.name,
        'instrument': parts[0],
        'voice': parts[1],
      });
    }
    UIUtils.showSnackbar(context, 'Stück gesendet: ${group.name}');
  }

  void _endPiece() {
    if (!_socket.isConnected || _currentPiece == null) return;
    _socket.send({'type': 'end_piece_signal', 'name': _currentPiece!.name});
    setState(() => _currentPiece = null);
  }

  void _filterPieces(String query) {
    _searchQuery = query;
    setState(() {
      if (query.isEmpty) {
        _filteredPieces = List.from(_pieces);
      } else {
        _filteredPieces = _pieces
            .where((p) =>
                p.name.toLowerCase().contains(query.toLowerCase().trim()))
            .toList();
      }
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_socket.isConnected) {
        _socket.send({'type': 'ping'});
        _startPongTimeout();
      } else {
        setState(() => _status = 'Getrennt');
      }
    });
  }

  void _startPongTimeout() {
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = Timer(_pongTimeout, () {
      setState(() => _status = 'Getrennt (keine Antwort)');
      _socket.disconnect();
    });
  }

  void _resetPongTimeout() {
    _pongTimeoutTimer?.cancel();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _socket.disconnect();
    super.dispose();
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
            onConnect: _socket.isConnected ? null : _socket.connect,
          ),
          if (_currentPiece != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: ElevatedButton.icon(
                onPressed: _endPiece,
                icon: const Icon(Icons.stop),
                label: const Text(
                  'Stück beenden',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade400,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 8,
                  shadowColor: Colors.redAccent.shade100,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Suche nach Stückname...',
                prefixIcon: const Icon(Icons.search, size: 22),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _filterPieces,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPieces.isEmpty
                    ? const Center(
                        child: Text(
                          'Keine Stücke gefunden',
                          style: TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: _filteredPieces.length,
                        itemBuilder: (_, i) {
                          final group = _filteredPieces[i];
                          final isActive = _currentPiece == group;
                          return _PieceCard(
                            group: group,
                            active: isActive,
                            onSend: () => _sendPiece(group),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final String status;
  final VoidCallback? onConnect;

  const _StatusHeader({required this.status, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final connected = status.toLowerCase().contains('verbunden');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, 8))
        ],
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.wifi : Icons.wifi_off,
            color: connected ? Colors.green : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: onConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Verbinden', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  final PieceGroup group;
  final bool active;
  final VoidCallback onSend;

  const _PieceCard({required this.group, required this.active, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final activeColor = Colors.deepPurpleAccent.shade100;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: active ? activeColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 6)),
        ],
        border: active ? Border.all(color: Colors.deepPurple, width: 2) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              group.name,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: active ? Colors.deepPurple : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Senden'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 6,
                  shadowColor: Colors.deepPurpleAccent.shade100,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
