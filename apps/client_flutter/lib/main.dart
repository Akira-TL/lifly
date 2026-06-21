import 'package:flutter/material.dart';
import 'package:client_flutter/app/shell/app_shell.dart';
import 'package:client_flutter/app/theme/app_theme.dart';

void main() {
  runApp(const LifilyApp());
}

class LifilyApp extends StatelessWidget {
  const LifilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lifily',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
