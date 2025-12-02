// lib/main.dart
import 'package:flutter/material.dart';
import 'musician_setup.dart';
import 'conductor_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Marschpad',
      theme: ThemeData.from(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const RoleSelectionPage(),
    );
  }
}

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marschpad - Rolle wählen')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              child: const Text('Ich bin Musiker'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MusicianSetupPage())),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              child: const Text('Ich bin Dirigent (Downloader + Host)'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConductorPage())),
            ),
          ],
        ),
      ),
    );
  }
}
