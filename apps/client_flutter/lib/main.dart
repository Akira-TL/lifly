import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/app/app_config.dart';
import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/app/shell/app_shell.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/powersync_connection_coordinator.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeRuntime>(create: (_) => ThemeRuntime()),
        Provider<LiflyDataMode>.value(value: AppConfig.dataMode),
        Provider<ApiClient>(
          create: (_) => ApiClient(baseUrl: AppConfig.apiBaseUrl),
        ),
        Provider<SyncService>(
          create: (context) => SyncService(api: context.read<ApiClient>()),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<PowerSyncConnectionCoordinator>(
          create: (context) => PowerSyncConnectionCoordinator(
            credentialsService: PowerSyncCredentialsService(
              context.read<ApiClient>(),
            ),
            syncService: context.read<SyncService>(),
          ),
        ),
        ProxyProvider<SyncService, LocalCoreBridge>(
          update: (_, syncService, _) =>
              PowerSyncLocalCoreBridge(syncService: syncService),
        ),
        ProxyProvider3<
          ApiClient,
          LiflyDataMode,
          LocalCoreBridge,
          AiCaptureService
        >(
          update: (_, api, dataMode, localCore, _) => AiCaptureService(
            api: api,
            dataMode: dataMode,
            localCore: localCore,
          ),
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
    final theme = context.watch<ThemeRuntime>().snapshot;

    return MaterialApp(
      title: 'Lifly',
      theme: theme.lightTheme,
      darkTheme: theme.darkTheme,
      themeMode: theme.themeMode,
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
