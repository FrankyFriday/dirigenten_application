import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import 'pages/conductor_page.dart';

/// =========================
/// APP ENTRY POINT
/// =========================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");

  runApp(const MyApp());
}

/// =========================
/// APP ROOT
/// =========================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Marschpad – Dirigent',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A1B9A),
        ),
        fontFamily: 'Roboto',
      ),
      home: const SplashLanding(),
    );
  }
}

/// =========================
/// SPLASH LANDING
/// =========================
class SplashLanding extends StatefulWidget {
  const SplashLanding({super.key});

  @override
  State<SplashLanding> createState() => _SplashLandingState();
}

class _SplashLandingState extends State<SplashLanding> {
  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  /// =========================
  /// UPDATE CHECK
  /// =========================
  Future<void> _checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version;

    final channel = WebSocketChannel.connect(
      Uri.parse('ws://ws.notenserver.duckdns.org'),
    );

    // Registrierung als Dirigent beim WebSocket-Server
    channel.sink.add(jsonEncode({
      'type': 'register',
      'role': 'conductor',
    }));

    // Nachrichten empfangen
    channel.stream.listen((msg) async {
      try {
        final data = jsonDecode(msg);

        if (data['type'] == 'release_announce' &&
            data['app'] == 'dirigenten_application' &&
            data['version'] != currentVersion) {
          // Neue Version gefunden → APK laden & installieren
          await _downloadAndInstall(data['apkUrl']);
        }
      } catch (e) {
        // Fehler loggen
        print('[UPDATE] Fehler: $e');
      }
    });

    // Nach 3 Sekunden weiter zur ConductorPage
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ConductorPage()),
      );
    });
  }

  /// =========================
  /// APK DOWNLOAD & INSTALL
  /// =========================
  Future<void> _downloadAndInstall(String url) async {
    try {
      final dir = await getExternalStorageDirectory();
      final file = File('${dir!.path}/update.apk');

      // APK herunterladen
      final res = await http.get(Uri.parse(url));
      await file.writeAsBytes(res.bodyBytes);

      // Android Installer Dialog
      await OpenFilex.open(file.path);
    } catch (e) {
      print('[UPDATE] Fehler beim Download/Install: $e');
    }
  }

  @override
  Widget build(BuildContext context) => const SplashScreen();
}

/// =========================
/// SPLASH SCREEN
/// =========================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4A148C),
              Color(0xFF7B1FA2),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.music_note,
                      size: 90,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Marschpad',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Musikverein Scharrel',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.75),
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
