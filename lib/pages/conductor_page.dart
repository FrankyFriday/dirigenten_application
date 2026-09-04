import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Für HapticFeedback
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../models/piece_group.dart';
import '../models/update_info.dart';
import '../services/nextcloud_service.dart';
import '../services/conductor_socket.dart';
import '../services/ui_utils.dart';
import '../services/version_checker.dart';
import '../ui/update_dialog.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ConductorPage extends ConsumerStatefulWidget {
  const ConductorPage({super.key});

  @override
  ConsumerState<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends ConsumerState<ConductorPage> {
  final NextcloudService _service = NextcloudService();
  late final ConductorSocket _socket;
  late final String _clientId;
  late final ScrollController _scrollController;

  List<PieceGroup> _pieces = [];
  List<PieceGroup> _filteredPieces = [];
  PieceGroup? _currentPiece;
  String _status = 'Nicht verbunden';
  bool _loading = true;
  String _searchQuery = '';

  // Werden über die 'status'-Nachricht des Servers befüllt
  // ({"type":"status","musicians":N,"conductors":M}).
  int _musicians = 0;
  int _conductors = 0;
  bool _maintenanceMode = false;

  // Verhindert, dass beim gleichen Release mehrfach ein Update-Dialog
  // angezeigt wird (z. B. wenn der Server das Release erneut broadcastet).
  bool _updateDialogShown = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
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
    // Hinweis: Ein eigener Client-seitiger Ping-Heartbeat ist hier nicht
    // nötig und würde nicht zum Server-Protokoll passen – der Server
    // (noten-server v2) initiiert selbst alle 30s ein 'ping' und erwartet
    // ein 'pong' vom Client (siehe unten, case 'ping'). Ein zusätzliches,
    // vom Client initiiertes 'ping' würde vom Server nicht als Heartbeat
    // erkannt, sondern (mangels eigener Behandlung) an alle verbundenen
    // Clients weitergebroadcastet.
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
        // Der Server sendet hier NICHT ein 'text'-Feld, sondern die Anzahl
        // verbundener Clients ({"type":"status","musicians":N,"conductors":M}).
        // Der Verbindungsstatus selbst (verbunden/getrennt/…) kommt separat
        // über den onStatusUpdate-Callback des Sockets (s. _status oben).
        setState(() {
          _musicians = (msg['musicians'] as num?)?.toInt() ?? _musicians;
          _conductors = (msg['conductors'] as num?)?.toInt() ?? _conductors;
        });
        break;

      case 'release_announce':
        await _handleReleaseAnnounce(msg);
        break;

      case 'maintenance_status':
        setState(() => _maintenanceMode = msg['enabled'] == true);
        if (_maintenanceMode) {
          UIUtils.showSnackbar(context, 'Server-Wartungsmodus ist aktiv.');
        }
        break;

      case 'admin_message':
        final text = msg['text'];
        if (text is String && text.isNotEmpty) {
          UIUtils.showSnackbar(context, text);
        }
        break;

      case 'ping':
        // Antwort auf den periodischen Server-Ping (Keepalive).
        _socket.send({'type': 'pong'});
        break;

      case 'send_piece_signal':
      case 'end_piece_signal':
        print('[WS] Server-Signal empfangen: $type');
        break;

      default:
        print('[WS] Unbekannter Typ: $type');
    }
  }

  /// Behandelt ein `release_announce` vom noten-server v2.
  ///
  /// Format vom Server (siehe noten-server/lib/models/release.dart):
  /// { "type": "release_announce", "app": "...",
  ///   "release": { "version": "...", "apkUrl": "...", "publishedAt": "..." } }
  ///
  /// Der Server kennt keine `mandatory`/`notes`-Felder wie das ursprüngliche
  /// `update.json`-Format – dafür werden hier sinnvolle Defaults gesetzt.
Future<void> _handleReleaseAnnounce(Map<String, dynamic> msg) async {
  print('[UPDATE] ========================================');
  print('[UPDATE] release_announce empfangen');
  print('[UPDATE] komplette Nachricht: $msg');

  if (msg['app'] != AppConfig.appId) {
    print(
      '[UPDATE] Falsche App-ID: '
      '${msg['app']} != ${AppConfig.appId}',
    );
    return;
  }

  final release = msg['release'];

  if (release is! Map) {
    print('[UPDATE] release fehlt oder ist kein Map');
    return;
  }

  final releaseMap = Map<String, dynamic>.from(release);

  final serverVersion = releaseMap['version'] as String?;
  final apkUrl = releaseMap['apkUrl'] as String?;

  print('[UPDATE] Server-Version: $serverVersion');
  print('[UPDATE] APK-URL: $apkUrl');

  if (serverVersion == null || apkUrl == null) {
    print('[UPDATE] Version oder APK-URL fehlt');
    return;
  }

  final packageInfo = await PackageInfo.fromPlatform();
  final currentVersion = packageInfo.version;

  print('[UPDATE] Installierte Version: $currentVersion');

  final isNewer = VersionChecker.isNewerVersion(
    currentVersion,
    serverVersion,
  );

  print('[UPDATE] Ist Server-Version neuer? $isNewer');

  if (!isNewer) {
    print(
      '[UPDATE] Kein Update erforderlich: '
      '$currentVersion -> $serverVersion',
    );
    return;
  }

  if (_updateDialogShown || !mounted) {
    print('[UPDATE] Update-Dialog bereits angezeigt oder Widget unmounted');
    return;
  }

  _updateDialogShown = true;

  print('[UPDATE] NEUES UPDATE ERKANNT');
  print('[UPDATE] Öffne Update-Dialog...');

  final updateInfo = UpdateInfo(
    version: serverVersion,
    mandatory: false,
    notes: 'Neues Release verfügbar.',
    url: apkUrl,
  );

  await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        return UpdateDialog(updateInfo: updateInfo);
      },
    ),
  );

  print('[UPDATE] Update-Dialog geschlossen');

  _updateDialogShown = false;
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

  @override
  void dispose() {
    _socket.disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F1F6),
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
            musicians: _musicians,
            conductors: _conductors,
            maintenanceMode: _maintenanceMode,
            onConnect: _socket.isConnected ? null : _socket.connect,
          ),
          if (_currentPiece != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.heavyImpact(); // Vibration beim Beenden
                  _endPiece();
                },
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
                    : Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          itemCount: _filteredPieces.length,
                          itemBuilder: (_, i) {
                            final group = _filteredPieces[i];
                            final isActive = _currentPiece == group;
                            return _PieceCard(
                              group: group,
                              active: isActive,
                              onSend: () {
                                HapticFeedback.lightImpact(); // Vibration beim Senden
                                _sendPiece(group);
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final String status;
  final int musicians;
  final int conductors;
  final bool maintenanceMode;
  final VoidCallback? onConnect;

  const _StatusHeader({
    required this.status,
    required this.onConnect,
    this.musicians = 0,
    this.conductors = 0,
    this.maintenanceMode = false,
  });

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              if (!connected)
                ElevatedButton(
                  onPressed: onConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child:
                      const Text('Verbinden', style: TextStyle(fontSize: 14)),
                ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 8),
            Text(
              '$musicians Musiker · $conductors Dirigenten verbunden',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
          if (maintenanceMode) ...[
            const SizedBox(height: 8),
            const Text(
              '⚠️ Server-Wartungsmodus aktiv',
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PieceCard extends StatefulWidget {
  final PieceGroup group;
  final bool active;
  final VoidCallback onSend;

  const _PieceCard({
    required this.group,
    required this.active,
    required this.onSend,
  });

  @override
  State<_PieceCard> createState() => _PieceCardState();
}

class _PieceCardState extends State<_PieceCard> {
  String? _selectedInstrumentVoice;

  @override
  void initState() {
    super.initState();
    if (widget.group.instrumentsAndVoices.isNotEmpty) {
      _selectedInstrumentVoice = widget.group.instrumentsAndVoices[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = Colors.deepPurpleAccent.shade100;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: widget.active ? activeColor : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, 6)),
        ],
        border: widget.active ? Border.all(color: Colors.deepPurple, width: 2) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stück-Name
            Text(
              widget.group.name,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: widget.active ? Colors.deepPurple : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Dropdown für Instrumente/Stimmen
            if (widget.group.instrumentsAndVoices.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _selectedInstrumentVoice,
                decoration: InputDecoration(
                  labelText: 'Instrument / Stimme',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: widget.group.instrumentsAndVoices
                    .map((iv) => DropdownMenuItem(
                          value: iv,
                          child: Text(iv),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedInstrumentVoice = value;
                  });
                },
              ),

            const SizedBox(height: 12),

            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: widget.onSend,
                icon: const Icon(Icons.send, size: 18),
                label: const Text('Senden'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
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
