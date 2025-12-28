import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/piece_group.dart';
import '../services/nextcloud_service.dart';
import '../services/server_service.dart';

class ConductorPage extends StatefulWidget {
  const ConductorPage({super.key});

  @override
  State<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends State<ConductorPage> {
  final NextcloudService _nextcloudService = NextcloudService();
  final ServerService _serverService = ServerService();
  final TextEditingController _portController = TextEditingController(text: '4041');

  List<PieceGroup> _cachedPieceGroups = [];
  bool _loadingPieces = false;
  PieceGroup? _currentPiece;

  String _serverStatus = 'Server nicht gestartet';

  @override
  void initState() {
    super.initState();
    _loadPieces();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // ================= NEXTCLOUD =================
  Future<void> _loadPieces() async {
    _safeSetState(() => _loadingPieces = true);
    try {
      _cachedPieceGroups = await _nextcloudService.loadPieces();
    } catch (e) {
      debugPrint('Fehler beim Laden von Nextcloud: $e');
    }
    _safeSetState(() => _loadingPieces = false);
  }

  // ================= SERVER =================
  Future<void> _startServer() async {
    final port = int.tryParse(_portController.text) ?? 4041;
    try {
      await _serverService.start(port);
      _safeSetState(() {
        _serverStatus = 'Server gestartet auf Port $port';
      });
    } catch (e) {
      _safeSetState(() {
        _serverStatus = 'Fehler beim Starten: $e';
      });
    }
  }

  Future<void> _stopServer() async {
    await _serverService.stop();
    _safeSetState(() {
      _currentPiece = null;
      _serverStatus = 'Server gestoppt';
    });
  }

  Future<void> _sendPieceFromNextcloud(String filename,
      {String? targetInstrument, String? targetVoice, PieceGroup? pieceGroup}) async {
    if (pieceGroup != null) _safeSetState(() => _currentPiece = pieceGroup);

    try {
      final bytes = await _nextcloudService.downloadPdf(filename);
      final msg = jsonEncode({
        'type': 'send_piece',
        'name': filename,
        'data': base64Encode(bytes),
        'instrument': targetInstrument,
        'voice': targetVoice,
      });

      final clients = _serverService.clientMap.values.where((c) =>
          targetInstrument == null ||
          targetVoice == null ||
          (c.instrument == targetInstrument && c.voice == targetVoice));

      for (var client in clients) {
        client.socket.add(msg);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Noten gesendet: $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Download von Nextcloud: $e')),
        );
      }
    }
  }

  void _sendEndPiece() {
    if (_currentPiece == null) return;

    final msg = jsonEncode({
      'type': 'end_piece',
      'name': _currentPiece!.name,
    });

    for (var c in _serverService.clientMap.values) {
      c.socket.add(msg);
    }

    _safeSetState(() => _currentPiece = null);
  }

  @override
  void dispose() {
    _serverService.stop();
    _portController.dispose();
    super.dispose();
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dirigent Dashboard'),
        centerTitle: true,
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
                color: _serverService.isRunning ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _serverService.isRunning ? Colors.green : Colors.red,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _serverService.isRunning ? Icons.cloud_done : Icons.cloud_off,
                    color: _serverService.isRunning ? Colors.green.shade700 : Colors.red.shade700,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _serverStatus,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _serverService.isRunning ? Colors.green.shade900 : Colors.red.shade900,
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
                    onPressed: _serverService.isRunning ? _stopServer : _startServer,
                    icon: Icon(_serverService.isRunning ? Icons.stop_circle : Icons.play_circle_fill, size: 26),
                    label: Text(
                      _serverService.isRunning ? 'Stoppen' : 'Starten',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      backgroundColor: _serverService.isRunning ? Colors.redAccent : Colors.deepPurple.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stück zu Ende Button
            ElevatedButton.icon(
              onPressed: _currentPiece == null ? null : _sendEndPiece,
              icon: const Icon(Icons.stop_circle, color: Colors.white),
              label: const Text('Stück zu Ende', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 28),

            // Nextcloud Noten
            Text(
              'Nextcloud Noten',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade900,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: _loadingPieces
                  ? const Center(child: CircularProgressIndicator())
                  : _cachedPieceGroups.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Noten gefunden.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black54),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _cachedPieceGroups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final group = _cachedPieceGroups[i];
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
                                    _safeSetState(() => _currentPiece = group);
                                    for (var iv in group.instrumentsAndVoices) {
                                      final parts = iv.split(' ');
                                      if (parts.length < 2) continue;
                                      final instrument = parts[0];
                                      final voice = parts[1];
                                      final filename = "${group.name}_${instrument}_${voice}.pdf";
                                      _sendPieceFromNextcloud(filename,
                                          targetInstrument: instrument, targetVoice: voice, pieceGroup: group);
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
