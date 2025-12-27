import 'dart:io';

class ClientInfo {
  final WebSocket socket;
  final String instrument;
  final String voice;

  ClientInfo({
    required this.socket,
    required this.instrument,
    required this.voice,
  });
}
