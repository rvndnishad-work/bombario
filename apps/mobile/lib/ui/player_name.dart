import 'dart:math';

import 'package:flutter/material.dart';

/// The display name used in rooms. Kept in memory for the app's lifetime;
/// accounts and persistence arrive with online play.
class PlayerName {
  static final ValueNotifier<String> value = ValueNotifier(
    'Player ${Random().nextInt(900) + 100}',
  );

  static String get current =>
      value.value.trim().isEmpty ? 'Player' : value.value.trim();
}

class PlayerNameField extends StatefulWidget {
  const PlayerNameField({super.key});

  @override
  State<PlayerNameField> createState() => _PlayerNameFieldState();
}

class _PlayerNameFieldState extends State<PlayerNameField> {
  late final TextEditingController _controller = TextEditingController(
    text: PlayerName.value.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLength: 12,

      decoration: const InputDecoration(
        labelText: 'Your name',
        counterText: '',
        isDense: true,
      ),
      onChanged: (v) => PlayerName.value.value = v,
    );
  }
}
