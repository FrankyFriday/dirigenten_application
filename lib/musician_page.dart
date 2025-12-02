// lib/musician_page.dart
import 'package:flutter/material.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'shared.dart';

class MusicianPage extends StatefulWidget {
  final String instrument;
  final String voice;
  final String conductorIp;
  final int conductorPort;
  const MusicianPage({super.key, required this.instrument, required this.voice, required this.conductorIp, required this.conductorPort});

  @override
  State<MusicianPage> createState() => _MusicianPageState();
}

class _MusicianPageState extends State<MusicianPage> {
  IOWebSocketChannel? _channel;
  bool _connectedToConductor = false;
  final List<ReceivedPiece> _received = [];
  String _status = 'Nicht verbunden mit Dirigent';
  late String _clientId;

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    // don't auto connect if no IP
    if (widget.conductorIp.isNotEmpty) {
      _tryConnect();
    }
  }

  Future<void> _tryConnect() async {
    final ip = widget.conductorIp;
    final port = widget.conductorPort;
    if (ip.isEmpty) {
      setState(() => _status = 'Keine Dirigent-IP konfiguriert');
      return;
    }
    final uri = 'ws://$ip:$port';
    try {
      final socket = await WebSocket.connect(uri);
      setState(() {
        _channel = IOWebSocketChannel(socket);
        _connectedToConductor = true;
        _status = 'Dirigent verbunden';
      });
      final reg = jsonEncode({
        'type': 'register',
        'clientId': _clientId,
        'instrument': widget.instrument,
        'voice': widget.voice,
      });
      _channel!.sink.add(reg);
      _channel!.stream.listen((message) async {
        await _handleMessage(message);
      }, onDone: () {
        setState(() {
          _connectedToConductor = false;
          _status = 'Verbindung beendet';
        });
      }, onError: (e) {
        setState(() {
          _connectedToConductor = false;
          _status = 'Fehler: $e';
        });
      });
    } catch (e) {
      setState(() {
        _connectedToConductor = false;
        _status = 'Keine Verbindung: $e';
      });
    }
  }

  Future<void> _handleMessage(dynamic message) async {
    try {
      final map = jsonDecode(message as String);
      final type = map['type'];
      if (type == 'send_piece') {
        final name = map['name'] ?? 'unknown.pdf';
        final targetInstrument = map['instrument'];
        final targetVoice = map['voice'];
        if (targetInstrument != null && targetInstrument != widget.instrument) return;
        if (targetVoice != null && targetVoice != widget.voice) return;
        final dataB64 = map['data'];
        final bytes = base64Decode(dataB64);
        final file = await saveBytesAsFile(bytes, name);
        setState(() {
          _received.add(ReceivedPiece(name: name, path: file.path, receivedAt: DateTime.now()));
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Neue Noten empfangen: $name')));
      } else if (type == 'status') {
        final text = map['text'] ?? '';
        setState(() => _status = text);
      } else if (type == 'catalog') {
        // optional: katalog info (list of pieces)
      }
    } catch (e) {
      debugPrint('Fehler beim Verarbeiten eingehender Nachricht: $e');
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Widget _buildReceivedList() {
    if (_received.isEmpty) return const Text('Keine Noten empfangen.');
    return ListView.builder(
      itemCount: _received.length,
      itemBuilder: (context, i) {
        final p = _received[i];
        return ListTile(
          title: Text(p.name),
          subtitle: Text(p.receivedAt.toString()),
          trailing: IconButton(icon: const Icon(Icons.open_in_new), onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Datei gespeichert: ${p.path}')));
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Musiker'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Instrument: ${widget.instrument}'),
            Text('Stimme: ${widget.voice}'),
            const SizedBox(height: 8),
            Text('Status: $_status', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _tryConnect, child: const Text('Mit Dirigent verbinden')),
            const SizedBox(height: 12),
            const Text('Erhaltene Noten:'),
            Expanded(child: _buildReceivedList()),
          ],
        ),
      ),
    );
  }
}
