import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/features/settings/account_device_runtime.dart';
import 'package:client_flutter/features/settings/widgets/account_device_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AccountAccessPage extends StatelessWidget {
  const AccountAccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Lifly',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '登录后同步你的加密数据与可信设备。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AccountDeviceSettingsSection(
                    api: context.read<ApiClient>(),
                    runtime: context.read<AccountDeviceRuntime>(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
