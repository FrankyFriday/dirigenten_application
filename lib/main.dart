import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pages/conductor_page.dart';
import 'providers/update_providers.dart';
import 'ui/update_dialog.dart';
import 'models/update_info.dart';

/// =========================
/// APP ENTRY POINT
/// =========================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  runApp(const ProviderScope(child: MyApp()));
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
class SplashLanding extends ConsumerStatefulWidget {
  const SplashLanding({super.key});

  @override
  ConsumerState<SplashLanding> createState() => _SplashLandingState();
}

class _SplashLandingState extends ConsumerState<SplashLanding> {
  @override
  void initState() {
    super.initState();

    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    final updateCheckNotifier = ref.read(updateCheckProvider.notifier);
    await updateCheckNotifier.checkForUpdate();

    final updateInfo = ref.read(updateCheckProvider).value;

    if (updateInfo != null && mounted) {
      final shouldUpdate = await showDialog<bool>(
        context: context,
        barrierDismissible: !updateInfo.mandatory,
        builder: (_) => UpdateDialog(updateInfo: updateInfo),
      );

      if (shouldUpdate == true) {
        // Update downloaded and installed, app may restart
        return;
      }
    }

    // Proceed to main app
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ConductorPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
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
                  // Kreis mit Musik-Icon
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

                  // App Name
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

                  // Untertitel
                  Text(
                    'Musikverein Scharrel',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.75),
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Ladeindikator
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
