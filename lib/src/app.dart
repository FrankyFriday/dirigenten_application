import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
  final String env;

  const MyApp({super.key, required this.env});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App ($env)',
      home: Scaffold(
        appBar: AppBar(title: Text('Environment: $env')),
        body: Center(child: Text('Running in $env mode')),
      ),
    );
  }
}
