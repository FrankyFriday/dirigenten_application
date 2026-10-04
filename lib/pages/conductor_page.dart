import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Für HapticFeedback
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/piece_group.dart';
import '../models/update_info.dart';
import '../services/nextcloud_service.dart';
import '../services/conductor_socket.dart';
import '../services/local_session_service.dart';
import '../services/ui_utils.dart';
import '../services/version_checker.dart';
import '../services/notification_service.dart';
import '../ui/update_dialog.dart';
import '../utils/logger.dart';
import '../theme/app_theme.dart';
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ConductorPage extends ConsumerStatefulWidget {
  const ConductorPage({super.key});

  @override
  ConsumerState<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends ConsumerState<ConductorPage>
    with WidgetsBindingObserver {
  final NextcloudService _service = NextcloudService();
  late final ConductorSocket _socket;
  late final String _clientId;
  late final ScrollController _scrollController;
  final TextEditingController _searchController = TextEditingController();
  static const _localNetworkChannel = MethodChannel('marschpad/local_network');
  final LocalSessionService _localSession = LocalSessionService();

  List<PieceGroup> _pieces = [];
  List<PieceGroup> _filteredPieces = [];
  PieceGroup? _currentPiece;
  String _status = 'Nicht verbunden';
  bool _loading = true;
  String? _piecesError;

  // Werden über die 'status'-Nachricht des Servers befüllt
  // ({"type":"status","musicians":N,"conductors":M}).
  int _musicians = 0;
  int _conductors = 0;
  bool _maintenanceMode = false;
  bool _offlineBackupEnabled = false;
  bool _usingLocalSession = false;

  // Verhindert, dass beim gleichen Release mehrfach ein Update-Dialog
  // angezeigt wird (z. B. wenn der Server das Release erneut broadcastet).
  bool _updateDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController();
    _clientId = const Uuid().v4();
    _socket = ConductorSocket(
      clientId: _clientId,
      onStatusUpdate: _handleSocketStatus,
      onMessage: _handleWSMessage,
    );
    _loadPieces();
    _loadOfflineBackupPreference();
    _socket.connect();
    // Hinweis: Ein eigener Client-seitiger Ping-Heartbeat ist hier nicht
    // nötig und würde nicht zum Server-Protokoll passen – der Server
    // (noten-server v2) initiiert selbst alle 30s ein 'ping' und erwartet
    // ein 'pong' vom Client (siehe unten, case 'ping'). Ein zusätzliches,
    // vom Client initiiertes 'ping' würde vom Server nicht als Heartbeat
    // erkannt, sondern (mangels eigener Behandlung) an alle verbundenen
    // Clients weitergebroadcastet.
  }

  Future<void> _loadOfflineBackupPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('offlineBackupEnabled') ?? false;
    if (!mounted || !enabled) return;
    setState(() => _offlineBackupEnabled = true);
    await _startLocalBackup();
  }

  void _handleSocketStatus(String status) {
    if (!mounted) return;
    final wasUsingLocalSession = _usingLocalSession;
    setState(() {
      if (status == 'Verbunden') {
        _usingLocalSession = false;
      } else if (status == 'Fehler' || status == 'Getrennt') {
        _usingLocalSession = _offlineBackupEnabled && _localSession.isRunning;
      }
      _status = _usingLocalSession ? 'Lokaler Probenmodus' : status;
    });
    if (_usingLocalSession && !wasUsingLocalSession) {
      UIUtils.showSnackbar(
        context,
        'Internetverbindung verloren – Steuerung läuft jetzt lokal.',
      );
    }
  }

  Future<void> _toggleOfflineBackup() async {
    final nextValue = !_offlineBackupEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offlineBackupEnabled', nextValue);
    if (!mounted) return;
    setState(() {
      _offlineBackupEnabled = nextValue;
      if (!nextValue) _usingLocalSession = false;
    });

    if (nextValue) {
      await _startLocalBackup();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Lokaler Probenmodus bereit'),
          content: Text(
            'Verbinde die Musikergeräte mit dem WLAN-Hotspot dieses Handys. '
            'Der lokale Server läuft unter ${_localSession.address ?? 'wird ermittelt'} '
            'und benötigt keine Internetverbindung.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Später'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await _localNetworkChannel
                      .invokeMethod<void>('openHotspotSettings');
                } on PlatformException catch (error) {
                  if (!mounted) return;
                  UIUtils.showSnackbar(
                    context,
                    'Hotspot-Einstellungen konnten nicht geöffnet werden: '
                    '${error.message}',
                  );
                }
              },
              icon: const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Hotspot öffnen'),
            ),
          ],
        ),
      );
    } else {
      await _localSession.stop();
      if (!mounted) return;
      setState(() {
        _usingLocalSession = false;
        _musicians = 0;
        if (!_socket.isConnected) _status = 'Getrennt';
      });
      UIUtils.showSnackbar(context, 'Offline-Fallback ausgeschaltet.');
    }
  }

  Future<void> _startLocalBackup() async {
    try {
      _localSession.onAddressChanged = (_) {
        if (mounted) setState(() {});
      };
      _localSession.onMusicianCountChanged = (count) {
        if (mounted) setState(() => _musicians = count);
      };
      await _localSession.start();
      if (!mounted) return;
      setState(() {});
      if (!_socket.isConnected &&
          (_status == 'Fehler' || _status == 'Getrennt')) {
        setState(() {
          _usingLocalSession = true;
          _status = 'Lokaler Probenmodus';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _offlineBackupEnabled = false;
        _usingLocalSession = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('offlineBackupEnabled', false);
      if (!mounted) return;
      UIUtils.showSnackbar(
        context,
        'Lokaler Server konnte nicht starten. '
        'Hotspot prüfen und erneut versuchen: $error',
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android kann TCP-Verbindungen während des Hintergrundbetriebs
      // unterbrechen. Beim Zurückkehren wird die Verbindung geprüft und bei
      // Bedarf mit erneuter Registrierung wiederhergestellt.
      _socket.reconnect();
    }
  }

  Future<void> _loadPieces() async {
    if (mounted) {
      setState(() {
        _loading = _pieces.isEmpty;
        _piecesError = null;
      });
    }
    SharedPreferences? prefs;
    String? cached;
    try {
      prefs = await SharedPreferences.getInstance();
      cached = prefs.getString('cachedConductorPieces');
    } catch (error, stackTrace) {
      UpdateLogger.error(
        'Gespeicherte Stückliste konnte nicht gelesen werden.',
        error,
        stackTrace,
      );
    }

    if (_pieces.isEmpty && cached != null) {
      try {
        final cachedPieces = _decodeCachedPieces(cached);
        if (cachedPieces.isNotEmpty && mounted) {
          setState(() {
            _pieces = cachedPieces;
            _filteredPieces = List.from(cachedPieces);
            _loading = false;
          });
        }
      } on FormatException {
        UpdateLogger.warning('Gespeicherte Stückliste ist ungültig.');
      } on TypeError {
        UpdateLogger.warning(
            'Gespeicherte Stückliste hat ein falsches Format.');
      }
    }
    try {
      final loadedPieces = await _service.loadPieces();
      if (!mounted) return;
      setState(() {
        _pieces = loadedPieces;
        _filteredPieces = List.from(loadedPieces);
      });
      try {
        await prefs?.setString(
          'cachedConductorPieces',
          jsonEncode(
            loadedPieces
                .map((piece) => {
                      'name': piece.name,
                      'instrumentsAndVoices': piece.instrumentsAndVoices,
                    })
                .toList(),
          ),
        );
      } catch (error, stackTrace) {
        UpdateLogger.error(
          'Stückliste konnte nicht lokal gespeichert werden.',
          error,
          stackTrace,
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (cached != null) {
        try {
          _pieces = _decodeCachedPieces(cached);
          if (_pieces.isNotEmpty) {
            _filteredPieces = List.from(_pieces);
            UIUtils.showSnackbar(
              context,
              'Server nicht erreichbar – gespeicherte Stückliste wird '
              'verwendet.',
            );
          } else {
            setState(() => _piecesError = e.toString());
          }
        } on FormatException {
          setState(() => _piecesError = e.toString());
        } on TypeError {
          setState(() => _piecesError = e.toString());
        }
      } else {
        setState(() => _piecesError = e.toString());
        if (!mounted) return;
        UIUtils.showSnackbar(context, 'Fehler beim Laden: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<PieceGroup> _decodeCachedPieces(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Gespeicherte Stückliste ist ungültig.');
    }
    return decoded
        .whereType<Map>()
        .map((entry) => PieceGroup(
              name: entry['name'] as String,
              instrumentsAndVoices: (entry['instrumentsAndVoices'] as List)
                  .whereType<String>()
                  .toList(),
            ))
        .toList();
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
        UpdateLogger.info('[WS] Server-Signal empfangen: $type');
        break;

      default:
        UpdateLogger.warning('[WS] Unbekannter Typ: $type');
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
    UpdateLogger.info('[UPDATE] release_announce empfangen');

    if (!AppConfig.matchesServerAppId(msg['app'])) {
      UpdateLogger.warning(
        '[UPDATE] Falsche App-ID: '
        '${msg['app']} != ${AppConfig.appId}',
      );
      return;
    }

    final release = msg['release'];

    if (release is! Map) {
      UpdateLogger.warning('[UPDATE] release fehlt oder ist kein Map');
      return;
    }

    final releaseMap = Map<String, dynamic>.from(release);

    final serverVersion = releaseMap['version'] as String?;
    final apkUrl = releaseMap['apkUrl'] as String?;

    UpdateLogger.info('[UPDATE] Server-Version: $serverVersion');
    UpdateLogger.info('[UPDATE] APK-URL: $apkUrl');

    if (serverVersion == null || apkUrl == null) {
      UpdateLogger.warning('[UPDATE] Version oder APK-URL fehlt');
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    UpdateLogger.info('[UPDATE] Installierte Version: $currentVersion');

    final isNewer = VersionChecker.isNewerVersion(
      currentVersion,
      serverVersion,
    );

    UpdateLogger.info('[UPDATE] Ist Server-Version neuer? $isNewer');

    if (!isNewer) {
      UpdateLogger.info(
        '[UPDATE] Kein Update erforderlich: '
        '$currentVersion -> $serverVersion',
      );
      return;
    }

    if (_updateDialogShown || !mounted) {
      UpdateLogger.info(
          '[UPDATE] Update-Dialog bereits angezeigt oder Widget unmounted');
      return;
    }

    await notificationService.showUpdateAvailable(serverVersion);
    if (!mounted) return;

    _updateDialogShown = true;

    UpdateLogger.info('[UPDATE] NEUES UPDATE ERKANNT');
    UpdateLogger.info('[UPDATE] Öffne Update-Dialog...');

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

    UpdateLogger.info('[UPDATE] Update-Dialog geschlossen');

    _updateDialogShown = false;
  }

  void _sendPiece(PieceGroup group) {
    if (!_socket.isConnected && !_usingLocalSession) return;
    setState(() => _currentPiece = group);
    for (var iv in group.instrumentsAndVoices) {
      final parts = iv.split(' ');
      if (parts.length < 2) continue;
      final message = {
        'type': 'send_piece_signal',
        'name': group.name,
        'instrument': parts[0],
        'voice': parts[1],
      };
      if (_usingLocalSession) {
        _localSession.send(message);
      } else {
        _socket.send(message);
      }
    }
    UIUtils.showSnackbar(context, 'Stück gesendet: ${group.name}');
  }

  void _endPiece() {
    if ((!_socket.isConnected && !_usingLocalSession) ||
        _currentPiece == null) {
      return;
    }
    final message = {
      'type': 'end_piece_signal',
      'name': _currentPiece!.name,
    };
    if (_usingLocalSession) {
      _localSession.send(message);
    } else {
      _socket.send(message);
    }
    setState(() => _currentPiece = null);
  }

  void _filterPieces(String query) {
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
    WidgetsBinding.instance.removeObserver(this);
    _socket.disconnect();
    _localSession.stop();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Marschpad'),
            Text(
              'DIRIGENTENPULT',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Stücke aktualisieren',
            onPressed: _loadPieces,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _StatusHeader(
              status: _status,
              musicians: _musicians,
              conductors: _conductors,
              maintenanceMode: _maintenanceMode,
              onConnect: _socket.isConnected ? null : _socket.connect,
            ),
            Card(
              margin: const EdgeInsets.fromLTRB(18, -8, 18, 12),
              child: SwitchListTile(
                value: _offlineBackupEnabled,
                onChanged: (_) => _toggleOfflineBackup(),
                secondary: const Icon(Icons.wifi_tethering_rounded),
                title: const Text('Lokalen Offline-Fallback'),
                subtitle: Text(
                  _usingLocalSession
                      ? 'Aktiv · Steuerung läuft lokal'
                      : 'Bereitet den Probenserver für Internet-Ausfälle vor',
                ),
              ),
            ),
            if (_offlineBackupEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: MaterialBanner(
                  content: Text(
                    _usingLocalSession
                        ? 'Offline aktiv · Hotspot-IP ${_localSession.address ?? 'wird ermittelt'}'
                        : 'Offline-Fallback bereit · Hotspot-IP '
                            '${_localSession.address ?? 'wird ermittelt'}',
                  ),
                  leading: const Icon(Icons.wifi_tethering_rounded),
                  actions: [
                    TextButton(
                      onPressed: _toggleOfflineBackup,
                      child: const Text('AUS'),
                    ),
                  ],
                ),
              ),
            if (_currentPiece != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: FilledButton.icon(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    _endPiece();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text('„${_currentPiece!.name}“ beenden'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: TextField(
                controller: _searchController,
                onChanged: _filterPieces,
                decoration: InputDecoration(
                  hintText: 'Stücke durchsuchen',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _filteredPieces.length != _pieces.length
                      ? IconButton(
                          tooltip: 'Suche löschen',
                          onPressed: () {
                            _searchController.clear();
                            _filterPieces('');
                          },
                          icon: const Icon(Icons.close_rounded),
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _piecesError != null
                      ? _MessageState(
                          icon: Icons.cloud_off_rounded,
                          title: 'Stücke nicht verfügbar',
                          message: _piecesError!,
                          actionLabel: 'Erneut laden',
                          onAction: _loadPieces,
                        )
                      : _filteredPieces.isEmpty
                          ? _MessageState(
                              icon: Icons.library_music_outlined,
                              title: _pieces.isEmpty
                                  ? 'Noch keine Stücke'
                                  : 'Nichts gefunden',
                              message: _pieces.isEmpty
                                  ? 'Die Notenbibliothek ist momentan leer.'
                                  : 'Passe den Suchbegriff an.',
                              actionLabel:
                                  _pieces.isEmpty ? 'Aktualisieren' : null,
                              onAction: _pieces.isEmpty ? _loadPieces : null,
                            )
                          : RefreshIndicator(
                              onRefresh: _loadPieces,
                              child: Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding:
                                      const EdgeInsets.fromLTRB(18, 0, 18, 28),
                                  itemCount: _filteredPieces.length,
                                  itemBuilder: (_, index) {
                                    final group = _filteredPieces[index];
                                    return _PieceCard(
                                      group: group,
                                      active: _currentPiece == group,
                                      onSend: () {
                                        HapticFeedback.lightImpact();
                                        _sendPiece(group);
                                      },
                                    );
                                  },
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
    final connected = status.toLowerCase() == 'verbunden';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.midnight, Color(0xFF0B5961)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.midnight.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: connected ? const Color(0xFF8DE3C0) : AppTheme.amber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Serververbindung',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        status,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!connected)
                  OutlinedButton(
                    onPressed: onConnect,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                    ),
                    child: const Text('Verbinden'),
                  ),
              ],
            ),
            if (connected) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  _ConnectionCount(
                    icon: Icons.headphones_rounded,
                    count: musicians,
                    label: 'Musiker',
                  ),
                  const SizedBox(width: 10),
                  _ConnectionCount(
                    icon: Icons.music_note_rounded,
                    count: conductors,
                    label: 'Dirigenten',
                  ),
                ],
              ),
            ],
            if (maintenanceMode) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: AppTheme.amber, size: 19),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Server-Wartungsmodus aktiv',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionCount extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;

  const _ConnectionCount({
    required this.icon,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, size: 17, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colors.secondary),
            const SizedBox(height: 15),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

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
    final colors = Theme.of(context).colorScheme;
    final voices = group.instrumentsAndVoices;
    return Card(
      color: active ? colors.secondaryContainer : null,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: active ? colors.primary : colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: active ? colors.onPrimary : colors.secondary,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    group.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: active ? colors.onSecondaryContainer : null,
                        ),
                  ),
                ),
                if (active)
                  Icon(Icons.graphic_eq_rounded, color: colors.secondary),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${voices.length} ${voices.length == 1 ? 'Stimme' : 'Stimmen'}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (voices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: voices
                    .map(
                      (voice) => Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(voice),
                        backgroundColor: active
                            ? colors.surface.withValues(alpha: 0.72)
                            : colors.surfaceContainerHighest,
                        side: BorderSide.none,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 15),
            ] else
              const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: voices.isEmpty ? null : onSend,
                icon: const Icon(Icons.send_rounded, size: 19),
                label: const Text('An alle Stimmen senden'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
