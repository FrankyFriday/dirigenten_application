import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/logger.dart';

class LocalSessionService {
  static const int _webSocketPort = 8765;
  static const int _discoveryPort = 8766;

  final Set<WebSocket> _musicians = {};
  final Map<WebSocket, String> _roles = {};
  HttpServer? _server;
  RawDatagramSocket? _discovery;
  Timer? _beacon;
  String? address;
  void Function(String address)? onAddressChanged;
  void Function(int musicianCount)? onMusicianCountChanged;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      _webSocketPort,
      shared: true,
    );
    try {
      final discovery = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      discovery.broadcastEnabled = true;
      _server = server;
      _discovery = discovery;
      try {
        address = await _findLocalAddress();
      } on SocketException {
        address = null;
      }
      server.listen(_handleRequest);
      _beacon = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _broadcastBeacon(),
      );
      onMusicianCountChanged?.call(0);
      _broadcastBeacon();
      UpdateLogger.info(
        'Lokaler Probenserver gestartet${address == null ? '' : ' auf $address'}',
      );
    } catch (_) {
      _discovery?.close();
      _discovery = null;
      await server.close(force: true);
      rethrow;
    }
  }

  Future<String> _findLocalAddress() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final addresses = interfaces
        .expand((interface) => interface.addresses)
        .where((ip) => !ip.isLoopback && !ip.isLinkLocal)
        .map((ip) => ip.address)
        .toList()
      ..sort((a, b) {
        final aRank = _addressRank(a);
        final bRank = _addressRank(b);
        return aRank == bRank ? a.compareTo(b) : aRank.compareTo(bRank);
      });
    if (addresses.isEmpty) {
      throw const SocketException(
        'Keine lokale IPv4-Adresse gefunden. Ist der Handy-Hotspot aktiv?',
      );
    }
    return addresses.first;
  }

  int _addressRank(String address) {
    if (address.startsWith('192.168.')) return 0;
    if (address.startsWith('10.')) return 1;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(address)) return 2;
    return 3;
  }

  void _broadcastBeacon() async {
    final discovery = _discovery;
    if (discovery == null) return;
    try {
      final currentAddress = await _findLocalAddress();
      if (address != currentAddress) {
        address = currentAddress;
        onAddressChanged?.call(currentAddress);
      }
      final payload = utf8.encode(jsonEncode({
        'type': 'marschpad_local_session',
        'host': address,
        'port': _webSocketPort,
      }));
      discovery.send(
        payload,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } on SocketException {
      return;
    } catch (error) {
      UpdateLogger.warning('Lokale Proben-Ankündigung fehlgeschlagen: $error');
    }
  }

  void _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen(
      (raw) => _handleMessage(socket, raw),
      onDone: () => _removeClient(socket),
      onError: (_) => _removeClient(socket),
      cancelOnError: true,
    );
  }

  void _handleMessage(WebSocket socket, Object? raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'];
      if (type == 'register') {
        final role = decoded['role'];
        if (role != 'musician' && role != 'conductor') return;
        _roles[socket] = role as String;
        if (role == 'musician') _musicians.add(socket);
        _sendStatus();
        return;
      }
      if (type == 'ping') {
        socket.add(jsonEncode({'type': 'pong'}));
        return;
      }
    } on FormatException catch (error, stackTrace) {
      UpdateLogger.error(
          'Ungültige lokale WebSocket-Nachricht', error, stackTrace);
    }
  }

  void send(Map<String, dynamic> message) {
    final encoded = jsonEncode(message);
    for (final musician in _musicians.toList()) {
      try {
        musician.add(encoded);
      } on WebSocketException {
        _removeClient(musician);
      }
    }
  }

  void _sendStatus() {
    final status = jsonEncode({
      'type': 'status',
      'musicians': _musicians.length,
      'conductors': _roles.values.where((role) => role == 'conductor').length,
    });
    for (final socket in _roles.keys.toList()) {
      try {
        socket.add(status);
      } on WebSocketException {
        _removeClient(socket);
      }
    }
    onMusicianCountChanged?.call(_musicians.length);
  }

  void _removeClient(WebSocket socket) {
    _roles.remove(socket);
    _musicians.remove(socket);
    _sendStatus();
  }

  Future<void> stop() async {
    _beacon?.cancel();
    _beacon = null;
    _discovery?.close();
    _discovery = null;
    for (final socket in _roles.keys.toList()) {
      await socket.close();
    }
    _roles.clear();
    _musicians.clear();
    final server = _server;
    _server = null;
    address = null;
    await server?.close(force: true);
  }
}
