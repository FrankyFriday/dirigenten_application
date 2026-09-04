import 'dart:convert';
import 'dart:io';
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

  ConductorSocket({
    required this.clientId,
    required this.onStatusUpdate,
    required this.onMessage,
  });

  Future<void> connect() async {
    const domain = AppConfig.wsDomain;
    onStatusUpdate('Verbinde…');

    try {
      final socket = await WebSocket.connect('wss://$domain');
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
        onDone: () => onStatusUpdate('Getrennt'),
        onError: (err) => onStatusUpdate('Fehler'),
      );
    } catch (e) {
      onStatusUpdate('Fehler');
      UpdateLogger.error('[WS] Fehler beim Verbinden', e);
    }
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  bool get isConnected => _channel != null;
}
