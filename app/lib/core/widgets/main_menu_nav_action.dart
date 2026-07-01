import 'package:flutter/material.dart';

/// App bar action that returns to the signed-in main menu (root route).
class MainMenuNavAction extends StatelessWidget {
  const MainMenuNavAction({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Main menu',
      icon: const Icon(Icons.home_outlined),
      onPressed: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }
}
