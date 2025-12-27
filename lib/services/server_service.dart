import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/client_info.dart';

class ServerService {
  HttpServer? _wsServer;
  final Map<String, ClientInfo> clientMap = {};
  RawDatagramSocket? _udpSocket;
  Timer? _broadcastTimer;

  bool get isRunning => _wsServer != null;

  Future<void> start(int port) async {
    _wsServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _wsServer!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleClient(socket);
      }
    });
    _startBroadcast(port);
  }

  void _handleClient(WebSocket socket) {
    final key = socket.hashCode.toString();
    socket.listen((data) {
      try {
        final map = jsonDecode(data as String);
        if (map['type'] == 'register') {
          clientMap[key] = ClientInfo(
            socket: socket,
            instrument: map['instrument'] ?? '',
            voice: map['voice'] ?? '',
          );
        }
      } catch (_) {}
    }, onDone: () => clientMap.remove(key));
  }

  Future<void> _startBroadcast(int port) async {
    final ip = await _getLocalIp();
    if (ip == null) return;

    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _udpSocket!.broadcastEnabled = true;

    final msg = jsonEncode({'type': 'conductor_discovery', 'ip': ip, 'port': port});

    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isRunning) return;
      _udpSocket!.send(
        utf8.encode(msg),
        InternetAddress("255.255.255.255"),
        4210,
      );
    });
  }

  Future<String?> _getLocalIp() async {
    for (var iface in await NetworkInterface.list()) {
      for (var addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }

  Future<void> stop() async {
    for (var c in clientMap.values) {
      try {
        c.socket.add(jsonEncode({'type': 'status', 'text': 'Dirigent beendet'}));
        await c.socket.close();
      } catch (_) {}
    }
    clientMap.clear();
    await _wsServer?.close(force: true);
    _broadcastTimer?.cancel();
    _udpSocket?.close();
    _wsServer = null;
  }
}
