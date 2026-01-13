import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/piece_group.dart';
import '../services/nextcloud_service.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:uuid/uuid.dart';

class ConductorPage extends StatefulWidget {
  const ConductorPage({super.key});

  @override
  State<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends State<ConductorPage> {
  final NextcloudService _nextcloudService = NextcloudService();
  WebSocketChannel? _channel;

  late final String _clientId;
  List<PieceGroup> _cachedPieceGroups = [];
  bool _loadingPieces = false;
  PieceGroup? _currentPiece;
  String _serverStatus = 'Nicht verbunden';

  static const double _radius = 16.0;

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    _loadPieces();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadPieces() async {
    _safeSetState(() => _loadingPieces = true);
    try {
      _cachedPieceGroups = await _nextcloudService.loadPieces();
    } catch (e) {
      _safeSetState(() => _loadingPieces = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden der Noten: $e')),
      );
      return;
    }
    _safeSetState(() => _loadingPieces = false);
  }

  Future<void> _connectToServer() async {
    const domain = 'ws.notenserver.duckdns.org';
    _safeSetState(() => _serverStatus = 'Verbinde…');

    try {
      final socket = await WebSocket.connect('wss://$domain').timeout(const Duration(seconds: 5));
      final channel = IOWebSocketChannel(socket);

      channel.sink.add(jsonEncode({
        'type': 'register',
        'clientId': _clientId,
        'role': 'conductor',
      }));

      channel.stream.listen(
        (message) {
          try {
            final map = jsonDecode(message as String);
            if (map['type'] == 'status') {
              final text = map['text'] as String? ?? '';
              _safeSetState(() => _serverStatus = text);
            }
          } catch (_) {}
        },
        onDone: _handleDisconnect,
        onError: _handleError,
      );

      _safeSetState(() {
        _channel = channel;
        _serverStatus = 'Verbunden mit Server';
      });
    } catch (e) {
      _handleError(e);
    }
  }

  void _handleDisconnect() {
    _safeSetState(() {
      _serverStatus = 'Verbindung beendet';
      _channel = null;
    });
  }

  void _handleError(Object e) {
    _safeSetState(() {
      _serverStatus = 'Fehler: $e';
      _channel = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('WebSocket Fehler: $e')),
    );
  }

  Future<void> _sendPiece(
    String filename, {
    String? targetInstrument,
    String? targetVoice,
    PieceGroup? pieceGroup,
  }) async {
    if (_channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nicht verbunden mit Server')),
      );
      return;
    }

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

      _channel!.sink.add(msg);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stück gesendet: $filename')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Senden: $e')),
      );
    }
  }

  void _sendEndPiece() {
    if (_channel == null || _currentPiece == null) return;

    _channel!.sink.add(jsonEncode({
      'type': 'end_piece',
      'name': _currentPiece!.name,
    }));

    _safeSetState(() => _currentPiece = null);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stück beendet')),
    );
  }

  @override
  void dispose() {
    _channel?.sink.close(status.goingAway);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = _channel != null;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Dirigent Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple.shade700,
        elevation: 4,
        shadowColor: Colors.deepPurple.shade300,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Server Status',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(_radius),
                      border: Border.all(
                        color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isConnected ? Icons.cloud_done : Icons.cloud_off,
                          color: isConnected ? Colors.green.shade700 : Colors.red.shade700,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _serverStatus,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isConnected ? Colors.green.shade900 : Colors.red.shade900,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: isConnected ? null : _connectToServer,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                          child: const Text(
                            'Verbinden',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _currentPiece == null ? null : _sendEndPiece,
                    icon: const Icon(Icons.stop_circle, color: Colors.white),
                    label: const Text('Stück zu Ende', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Nextcloud Noten',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple.shade900,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            // ================= Scrollbare Liste =================
            Expanded(
              child: _loadingPieces
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _cachedPieceGroups.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final group = _cachedPieceGroups[i];
                        return Card(
                          elevation: 5,
                          shadowColor: Colors.deepPurple.shade100,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.deepPurple.shade50,
                              child: const Icon(Icons.picture_as_pdf, color: Colors.deepPurple, size: 32),
                            ),
                            title: Text(
                              group.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              group.instrumentsAndVoices.join(', '),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
                              ),
                            ),
                            trailing: ElevatedButton.icon(
                              icon: const Icon(Icons.send),
                              label: const Text('Senden'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                _safeSetState(() => _currentPiece = group);
                                for (var iv in group.instrumentsAndVoices) {
                                  final parts = iv.split(' ');
                                  if (parts.length < 2) continue;
                                  _sendPiece(
                                    "${group.name}_${parts[0]}_${parts[1]}.pdf",
                                    targetInstrument: parts[0],
                                    targetVoice: parts[1],
                                    pieceGroup: group,
                                  );
                                }
                              },
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
