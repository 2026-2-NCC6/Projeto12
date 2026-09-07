import 'package:flutter/material.dart';

void main() {
  runApp(const SmartTennisArenaApp());
}

class SmartTennisArenaApp extends StatelessWidget {
  const SmartTennisArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Radonix APP',
      home: Scaffold(
        appBar: AppBar(title: const Text('Radonix')),
        body: const Center(child: Text('Hello, Radonix!')),
      ),
    );
  }
}
