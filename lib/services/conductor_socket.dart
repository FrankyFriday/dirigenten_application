import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

typedef WSStatusCallback = void Function(String status);
typedef WSMessageCallback = void Function(Map<String, dynamic> message);

class ConductorSocket {
  final String clientId;
  final WSStatusCallback onStatusUpdate;
  final WSMessageCallback onMessage;
  WebSocketChannel? _channel;
  bool _connecting = false;
  bool _disposed = false;
  Timer? _reconnectTimer;

  ConductorSocket({
    required this.clientId,
    required this.onStatusUpdate,
    required this.onMessage,
  });

  Future<void> connect() async {
    if (_disposed || _connecting || isConnected) return;

    _connecting = true;
    const domain = AppConfig.wsDomain;
    onStatusUpdate('Verbinde…');

    try {
      final socket = await WebSocket.connect('wss://$domain');
      if (_disposed) {
        await socket.close();
        return;
      }

      _channel = IOWebSocketChannel(socket);
      onStatusUpdate('Verbunden');

      // Registrierung beim Server. Der Server erwartet `role` und `app`
      // (siehe noten-server bin/server.dart, _handleWebSocketMessage
      // case 'register'). Nur mit gesetztem `app` schickt der Server beim
      // Verbinden sofort den Wartungsstatus *und* das aktuell hinterlegte
      // Release für diese App mit.
      _channel!.sink.add(jsonEncode({
        'type': 'register',
        'clientId': clientId,
        'role': 'conductor',
        'app': AppConfig.appId,
      }));

      _channel!.stream.listen(
        (msg) {
          try {
            final map = jsonDecode(msg as String);
            final type = map['type'];

            switch (type) {
              case 'status':
              case 'release_announce':
              case 'maintenance_status':
              case 'admin_message':
              case 'send_piece_signal':
              case 'end_piece_signal':
              case 'ping':
                onMessage(map); // Leite bekannte Typen weiter
                break;
              default:
                UpdateLogger.warning('[WS] Unbekannter Typ: $type');
            }
          } catch (e) {
            UpdateLogger.error('[WS] JSON Parsing Fehler', e);
            UpdateLogger.warning('[WS] Raw message: $msg');
          }
        },
        onDone: _handleConnectionLost,
        onError: (err) => _handleConnectionLost(),
      );
    } catch (e) {
      onStatusUpdate('Fehler');
      UpdateLogger.error('[WS] Fehler beim Verbinden', e);
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void reconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
    connect();
  }

  void _handleConnectionLost() {
    _channel = null;
    if (_disposed) return;
    onStatusUpdate('Getrennt');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      connect();
    });
  }

  bool get isConnected => _channel != null;
}
