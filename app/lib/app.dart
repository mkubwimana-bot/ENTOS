import 'package:flutter/material.dart';

import 'features/auth/auth_gate.dart';

class SmeOsApp extends StatelessWidget {
  const SmeOsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SME-OS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: const AuthGate(),
    );
  }
}
