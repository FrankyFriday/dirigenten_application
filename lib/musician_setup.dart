// lib/musician_setup.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'musician_page.dart';

class MusicianSetupPage extends StatefulWidget {
  const MusicianSetupPage({super.key});
  @override
  State<MusicianSetupPage> createState() => _MusicianSetupPageState();
}

class _MusicianSetupPageState extends State<MusicianSetupPage> {
  final _instruments = ['Flöte', 'Klarinette', 'Trompete', 'Horn', 'Posaune', 'Schlagzeug', 'Sonstiges'];
  final _voices = ['1. Stimme', '2. Stimme', '3. Stimme', 'Bass', 'Solo'];
  String? _selectedInstrument;
  String? _selectedVoice;
  final _conductorIpController = TextEditingController();
  final _conductorPortController = TextEditingController(text: '4040');

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedInstrument = prefs.getString('instrument');
      _selectedVoice = prefs.getString('voice');
      _conductorIpController.text = prefs.getString('conductor_ip') ?? '';
      _conductorPortController.text = prefs.getString('conductor_port') ?? '4040';
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedInstrument != null) await prefs.setString('instrument', _selectedInstrument!);
    if (_selectedVoice != null) await prefs.setString('voice', _selectedVoice!);
    await prefs.setString('conductor_ip', _conductorIpController.text);
    await prefs.setString('conductor_port', _conductorPortController.text);
  }

  void _openMusician() async {
    if (_selectedInstrument == null || _selectedVoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Instrument und Stimme wählen.')));
      return;
    }
    await _savePrefs();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MusicianPage(
      instrument: _selectedInstrument!,
      voice: _selectedVoice!,
      conductorIp: _conductorIpController.text,
      conductorPort: int.tryParse(_conductorPortController.text) ?? 4040,
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Musiker - Setup')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wähle dein Instrument'),
            DropdownButton<String>(
              value: _selectedInstrument,
              hint: const Text('Instrument wählen'),
              isExpanded: true,
              items: _instruments.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _selectedInstrument = v),
            ),
            const SizedBox(height: 12),
            const Text('Wähle deine Stimme'),
            DropdownButton<String>(
              value: _selectedVoice,
              hint: const Text('Stimme wählen'),
              isExpanded: true,
              items: _voices.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _selectedVoice = v),
            ),
            const SizedBox(height: 12),
            const Divider(),
            const Text('Dirigent (lokale IP im Marsch-WLAN)'),
            TextField(controller: _conductorIpController, decoration: const InputDecoration(labelText: 'IP-Adresse (z.B. 192.168.1.12)'),),
            TextField(controller: _conductorPortController, decoration: const InputDecoration(labelText: 'Port'), keyboardType: TextInputType.number,),
            const SizedBox(height: 16),
            Center(child: ElevatedButton(child: const Text('Weiter als Musiker'), onPressed: _openMusician)),
          ],
        ),
      ),
    );
  }
}
