import 'package:flutter/material.dart';

import 'features/notes/notes_workspace_page.dart';

class MnemosyneApp extends StatelessWidget {
  const MnemosyneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1C6E5B),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Mnemosyne',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF5F2E8),
        useMaterial3: true,
      ),
      home: const NotesWorkspacePage(),
    );
  }
}
