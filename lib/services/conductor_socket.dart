import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
    const domain = 'ws.notenserver.duckdns.org';
    onStatusUpdate('Verbinde…');

    try {
      final socket = await WebSocket.connect('wss://$domain');
      _channel = IOWebSocketChannel(socket);
      onStatusUpdate('Verbunden');

      // Registrierung beim Server
      _channel!.sink.add(jsonEncode({
        'type': 'register',
        'clientId': clientId,
        'role': 'conductor',
      }));

      _channel!.stream.listen(
        (msg) {
          try {
            final map = jsonDecode(msg as String);
            final type = map['type'];

            switch (type) {
              case 'status':
              case 'release_announce':
              case 'send_piece_signal':
              case 'end_piece_signal':
              case 'ping':
                onMessage(map); // Leite bekannte Typen weiter
                break;
              default:
                print('[WS] Unbekannter Typ: $type');
            }
          } catch (e) {
            print('[WS] JSON Parsing Fehler: $e');
            print('Raw msg: $msg');
          }
        },
        onDone: () => onStatusUpdate('Getrennt'),
        onError: (err) => onStatusUpdate('Fehler'),
      );
    } catch (e) {
      onStatusUpdate('Fehler');
      print('[WS] Fehler beim Verbinden: $e');
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
