import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/app/app_config.dart';
import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/app/shell/app_shell.dart';
import 'package:client_flutter/app/theme/app_theme.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider<LiflyDataMode>.value(value: AppConfig.dataMode),
        Provider<ApiClient>(
          create: (_) => ApiClient(baseUrl: AppConfig.apiBaseUrl),
        ),
        Provider<SyncService>(
          create: (_) => SyncService(),
          dispose: (_, service) => service.dispose(),
        ),
        ProxyProvider<SyncService, LocalCoreBridge>(
          update: (_, syncService, _) =>
              PowerSyncLocalCoreBridge(syncService: syncService),
        ),
      ],
      child: const LiflyApp(),
    ),
  );
}

class LiflyApp extends StatelessWidget {
  const LiflyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lifly',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
