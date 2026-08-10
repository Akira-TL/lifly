import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/app/app_config.dart';
import 'package:client_flutter/app/data_mode.dart';
import 'package:client_flutter/app/shell/app_shell.dart';
import 'package:client_flutter/app/startup/startup_metrics.dart';
import 'package:client_flutter/app/theme/theme_cache_bootstrapper.dart';
import 'package:client_flutter/app/theme/theme_entitlement.dart';
import 'package:client_flutter/app/theme/theme_integrity.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_package_cache_factory.dart';
import 'package:client_flutter/app/theme/theme_platform.dart';
import 'package:client_flutter/app/theme/theme_preferences.dart';
import 'package:client_flutter/app/theme/theme_registry.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:client_flutter/app/theme/theme_tokens.dart';
import 'package:client_flutter/app/theme/themes/lifly_test_theme.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/local_core/fake_local_core_bridge.dart';
import 'package:client_flutter/data/local_core/local_core_bridge.dart';
import 'package:client_flutter/data/local_core/powersync_local_core_bridge.dart';
import 'package:client_flutter/data/powersync/powersync_connection_coordinator.dart';
import 'package:client_flutter/data/powersync/powersync_credentials_service.dart';
import 'package:client_flutter/data/powersync/sync_service.dart';
import 'package:client_flutter/features/ai_capture/data/ai_capture_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  StartupMetrics.markDartEntrypoint();
  final useVisualFixtures = kDebugMode && AppConfig.visualFixtures;
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeRuntime>(
          create: (_) {
            final packages = kDebugMode
                ? <ThemePackage>[
                    ThemePackage.fromJson(liflyTestThemePackageJson),
                  ]
                : const <ThemePackage>[];
            final platform = currentThemeTargetPlatform();
            final registry = ThemeRegistry(packages: packages);
            final runtime = ThemeRuntime(
              registry: registry,
              preferenceStore: SharedPreferencesThemePreferenceStore(),
              appVersion: AppConfig.appVersion,
              platform: platform,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(
                _restoreThemesAfterCoreFrame(
                  runtime: runtime,
                  registry: registry,
                  platform: platform,
                ),
              );
            });
            return runtime;
          },
        ),
        Provider<LiflyDataMode>.value(
          value: useVisualFixtures ? LiflyDataMode.local : AppConfig.dataMode,
        ),
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
          update: (_, syncService, previous) {
            if (useVisualFixtures) {
              return previous is VisualFixtureLocalCoreBridge
                  ? previous
                  : VisualFixtureLocalCoreBridge();
            }
            return PowerSyncLocalCoreBridge(syncService: syncService);
          },
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
  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupMetrics.markFlutterFirstFrame();
    StartupMetrics.markCoreUsable();
  });
}

Future<void> _restoreThemesAfterCoreFrame({
  required ThemeRuntime runtime,
  required ThemeRegistry registry,
  required ThemeTargetPlatform platform,
}) async {
  await runtime.restore();
  StartupMetrics.markThemeActivated(runtime.snapshot.familyId);
  try {
    final cache = await openDefaultThemePackageCache();
    final bootstrapper = ThemeCacheBootstrapper(
      cache: cache,
      integrityVerifier: ThemePackageIntegrityVerifier(
        signatureVerifier: kDebugMode
            ? const LocalThemeSignatureVerifier()
            : const RejectingThemeSignatureVerifier(),
      ),
      entitlementProvider: LocalThemeEntitlementProvider(),
      appVersion: AppConfig.appVersion,
      platform: platform,
    );
    final cached = await bootstrapper.load();
    if (cached.packages.isEmpty) return;
    registry.registerPackages(cached.packages);
    await runtime.restore();
    StartupMetrics.markThemeActivated(runtime.snapshot.familyId);
  } catch (error) {
    StartupMetrics.markThemeRestoreFailed(error);
  }
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
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!MediaQuery.disableAnimationsOf(context)) return content;
        return Theme(
          data: themeWithReducedMotion(Theme.of(context)),
          child: content,
        );
      },
      home: const AppShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}
