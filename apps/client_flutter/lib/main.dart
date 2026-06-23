import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/app/shell/app_shell.dart';
import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/data/api/api_client.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>(create: (_) => ApiClient()),
      ],
      child: const LifilyApp(),
    ),
  );
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
