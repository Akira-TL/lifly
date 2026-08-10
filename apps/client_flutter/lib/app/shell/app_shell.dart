import 'dart:async';

import 'package:client_flutter/app/shell/shell_layout_policy.dart';
import 'package:client_flutter/app/shell/shell_preferences.dart';
import 'package:client_flutter/app/shell/wide_shell.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:client_flutter/features/ai_capture/pages/ai_capture_page.dart';
import 'package:client_flutter/features/home/pages/home_page.dart';
import 'package:client_flutter/features/ledger/pages/ledger_list_page.dart';
import 'package:client_flutter/features/management/pages/management_hub_page.dart';
import 'package:client_flutter/features/memo/pages/memo_list_page.dart';
import 'package:client_flutter/features/search/pages/search_page.dart';
import 'package:client_flutter/features/settings/settings_page.dart';
import 'package:client_flutter/features/task/pages/task_list_page.dart';
import 'package:flutter/material.dart';

class AppShell extends StatefulWidget {
  final ShellPreferenceStore? preferenceStore;

  const AppShell({super.key, this.preferenceStore});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _primaryDestinationIndex = 2;
  static const _destinations = <ShellDestination>[
    ShellDestination(
      label: '首页',
      webLabel: '今天',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      page: HomePage(),
    ),
    ShellDestination(
      label: '备忘',
      icon: Icons.note_outlined,
      selectedIcon: Icons.note,
      page: MemoListPage(),
    ),
    ShellDestination(
      label: 'AI',
      webLabel: 'AI 会话',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      page: AiCapturePage(),
    ),
    ShellDestination(
      label: '记账',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      page: LedgerListPage(),
    ),
    ShellDestination(
      label: '任务',
      icon: Icons.check_circle_outline,
      selectedIcon: Icons.check_circle,
      page: TaskListPage(),
    ),
  ];

  late final ShellPreferenceStore _preferenceStore;
  int _currentIndex = 0;
  bool _sidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    final providedStore = widget.preferenceStore;
    if (providedStore != null) {
      _preferenceStore = providedStore;
    } else {
      try {
        _preferenceStore = SharedPreferencesShellPreferenceStore();
      } catch (_) {
        _preferenceStore = const NoopShellPreferenceStore();
      }
    }
    unawaited(_restoreShellPreferences());
  }

  Future<void> _restoreShellPreferences() async {
    bool? collapsed;
    int? destinationIndex;
    try {
      collapsed = await _preferenceStore.loadSidebarCollapsed();
    } catch (_) {
      // A preference failure must not block the product shell.
    }
    try {
      destinationIndex = await _preferenceStore.loadDestinationIndex();
    } catch (_) {
      // A preference failure must not block the product shell.
    }
    if (!mounted) return;
    final validDestination =
        destinationIndex != null &&
        destinationIndex >= 0 &&
        destinationIndex < _destinations.length;
    if (collapsed == null && !validDestination) return;
    setState(() {
      if (collapsed != null) _sidebarCollapsed = collapsed;
      if (validDestination) _currentIndex = destinationIndex!;
    });
  }

  void _selectDestination(int index) {
    if (index < 0 || index >= _destinations.length || _currentIndex == index) {
      return;
    }
    setState(() => _currentIndex = index);
    unawaited(_preferenceStore.saveDestinationIndex(index).catchError((_) {}));
  }

  void _toggleSidebar() {
    final collapsed = !_sidebarCollapsed;
    setState(() => _sidebarCollapsed = collapsed);
    unawaited(
      _preferenceStore.saveSidebarCollapsed(collapsed).catchError((_) {}),
    );
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final profile =
            Theme.of(context).extension<ThemePlatformProfile>() ??
            ThemePlatformProfile.defaults(ThemeTargetPlatform.phone);
        final layout = ShellLayoutPolicy.resolve(
          width: constraints.maxWidth,
          profile: profile,
        );
        if (layout.useNavigationRail) {
          final theme = Theme.of(context);
          final wideTheme = theme.copyWith(
            textTheme: theme.textTheme.apply(fontSizeFactor: 1.06),
          );
          return Theme(
            data: wideTheme,
            child: WideShell(
              currentIndex: _currentIndex,
              destinations: _destinations,
              layout: layout,
              keyboardNavigation: profile.keyboardNavigation,
              sidebarCollapsed: _sidebarCollapsed,
              onDestinationSelected: _selectDestination,
              onQuickCapture: () =>
                  _selectDestination(_primaryDestinationIndex),
              onOpenSearch: () => _openPage(context, const SearchPage()),
              onOpenManagement: () =>
                  _openPage(context, const ManagementHubPage()),
              onOpenSettings: () => _openPage(context, const SettingsPage()),
              onToggleSidebar: _toggleSidebar,
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _destinations.map((item) => item.page).toList(),
          ),
          bottomNavigationBar: _MobileShellNavigationBar(
            currentIndex: _currentIndex,
            height: layout.mobileNavigationHeight,
            primaryDestinationIndex: _primaryDestinationIndex,
            destinations: _destinations,
            onDestinationSelected: _selectDestination,
          ),
        );
      },
    );
  }
}

class _MobileShellNavigationBar extends StatelessWidget {
  final int currentIndex;
  final double height;
  final int primaryDestinationIndex;
  final List<ShellDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  const _MobileShellNavigationBar({
    required this.currentIndex,
    required this.height,
    required this.primaryDestinationIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < destinations.length; index++)
                if (index == primaryDestinationIndex)
                  Expanded(
                    child: _PrimaryDestinationButton(
                      selected: currentIndex == index,
                      destination: destinations[index],
                      onTap: () => onDestinationSelected(index),
                    ),
                  )
                else
                  Expanded(
                    child: _ShellDestinationButton(
                      selected: currentIndex == index,
                      destination: destinations[index],
                      onTap: () => onDestinationSelected(index),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellDestinationButton extends StatelessWidget {
  final bool selected;
  final ShellDestination destination;
  final VoidCallback onTap;

  const _ShellDestinationButton({
    required this.selected,
    required this.destination,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        key: Key('shell_destination_${destination.label}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                destination.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryDestinationButton extends StatelessWidget {
  final bool selected;
  final ShellDestination destination;
  final VoidCallback onTap;

  const _PrimaryDestinationButton({
    required this.selected,
    required this.destination,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onPrimaryContainer;
    final background = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.primaryContainer;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        key: Key('shell_destination_${destination.label}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: foreground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
