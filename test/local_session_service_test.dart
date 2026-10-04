import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marschpad/services/local_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalSessionService session;

  setUp(() {
    session = LocalSessionService();
  });

  tearDown(() async {
    await session.stop();
  });

  test('relays conductor signals to musicians in the local session', () async {
    await session.start();
    final musician = await WebSocket.connect('ws://127.0.0.1:8765');
    final registration = Completer<void>();
    final signal = Completer<Map<String, dynamic>>();
    musician.listen((message) {
      final decoded = jsonDecode(message as String) as Map<String, dynamic>;
      if (decoded['type'] == 'status' && !registration.isCompleted) {
        registration.complete();
      } else if (decoded['type'] == 'send_piece_signal' &&
          !signal.isCompleted) {
        signal.complete(decoded);
      }
    });

    musician.add(jsonEncode({
      'type': 'register',
      'role': 'musician',
      'clientId': 'test-musician',
    }));
    await registration.future.timeout(const Duration(seconds: 3));

    const pieceSignal = {
      'type': 'send_piece_signal',
      'name': 'Testmarsch',
      'instrument': 'Trompete',
      'voice': '1',
    };
    session.send(pieceSignal);

    expect(
      await signal.future.timeout(const Duration(seconds: 3)),
      pieceSignal,
    );
    await musician.close();
  });
}
