import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_runtime.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThemeSettingsSection extends StatefulWidget {
  const ThemeSettingsSection({super.key});

  @override
  State<ThemeSettingsSection> createState() => _ThemeSettingsSectionState();
}

class _ThemeSettingsSectionState extends State<ThemeSettingsSection> {
  bool _saving = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('主题切换失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = context.watch<ThemeRuntime>();
    final selectedFamily = runtime.installedThemes.firstWhere(
      (theme) => theme.familyId == runtime.preference.familyId,
      orElse: () => runtime.installedThemes.first,
    );
    final modes = <ThemePackageColorMode>{
      ThemePackageColorMode.system,
      ThemePackageColorMode.light,
      ThemePackageColorMode.dark,
      ...selectedFamily.supportedColorModes.where(
        (mode) =>
            mode == ThemePackageColorMode.oled ||
            mode == ThemePackageColorMode.highContrast,
      ),
      runtime.preference.colorMode,
    }.toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette_outlined),
                const SizedBox(width: 8),
                Text('外观', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (_saving)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('theme_family_selector'),
              initialValue: runtime.preference.familyId,
              decoration: const InputDecoration(labelText: '主题'),
              items: [
                for (final theme in runtime.installedThemes)
                  DropdownMenuItem(
                    value: theme.familyId,
                    child: Text(theme.displayName),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (familyId) {
                      if (familyId == null ||
                          familyId == runtime.preference.familyId) {
                        return;
                      }
                      _run(() => runtime.selectFamily(familyId));
                    },
            ),
            const SizedBox(height: 16),
            Text('色彩模式', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ThemePackageColorMode>(
                key: const Key('theme_color_mode_selector'),
                segments: [
                  for (final mode in modes)
                    ButtonSegment(
                      value: mode,
                      label: Text(_modeLabel(mode)),
                      icon: Icon(_modeIcon(mode)),
                    ),
                ],
                selected: {runtime.preference.colorMode},
                onSelectionChanged: _saving
                    ? null
                    : (selection) {
                        final mode = selection.first;
                        if (mode == runtime.preference.colorMode) return;
                        _run(() => runtime.selectColorMode(mode));
                      },
              ),
            ),
            if (runtime.preference.colorMode != runtime.resolvedColorMode) ...[
              const SizedBox(height: 10),
              Text(
                '当前主题不支持该模式，已使用${_modeLabel(runtime.resolvedColorMode)}。',
                key: const Key('theme_color_mode_fallback'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _modeLabel(ThemePackageColorMode mode) {
  return switch (mode) {
    ThemePackageColorMode.system => '跟随系统',
    ThemePackageColorMode.light => '浅色',
    ThemePackageColorMode.dark => '深色',
    ThemePackageColorMode.oled => 'OLED',
    ThemePackageColorMode.highContrast => '高对比度',
  };
}

IconData _modeIcon(ThemePackageColorMode mode) {
  return switch (mode) {
    ThemePackageColorMode.system => Icons.brightness_auto_outlined,
    ThemePackageColorMode.light => Icons.light_mode_outlined,
    ThemePackageColorMode.dark => Icons.dark_mode_outlined,
    ThemePackageColorMode.oled => Icons.contrast_outlined,
    ThemePackageColorMode.highContrast => Icons.visibility_outlined,
  };
}
