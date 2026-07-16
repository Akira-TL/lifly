import 'package:client_flutter/app/shell/shell_layout_policy.dart';
import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:client_flutter/app/theme/theme_platform_profile.dart';
import 'package:flutter/material.dart';
import 'package:client_flutter/features/ai_capture/pages/ai_capture_page.dart';
import 'package:client_flutter/features/home/pages/home_page.dart';
import 'package:client_flutter/features/ledger/pages/ledger_list_page.dart';
import 'package:client_flutter/features/memo/pages/memo_list_page.dart';
import 'package:client_flutter/features/task/pages/task_list_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _primaryDestinationIndex = 2;
  static const _destinations = <_ShellDestination>[
    _ShellDestination(
      label: '首页',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      page: HomePage(),
    ),
    _ShellDestination(
      label: '备忘',
      icon: Icons.note_outlined,
      selectedIcon: Icons.note,
      page: MemoListPage(),
    ),
    _ShellDestination(
      label: 'AI',
      icon: Icons.auto_awesome_outlined,
      selectedIcon: Icons.auto_awesome,
      page: AiCapturePage(),
    ),
    _ShellDestination(
      label: '记账',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      page: LedgerListPage(),
    ),
    _ShellDestination(
      label: '任务',
      icon: Icons.check_circle_outline,
      selectedIcon: Icons.check_circle,
      page: TaskListPage(),
    ),
  ];

  int _currentIndex = 0;

  void _selectDestination(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
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
          return _WideShell(
            currentIndex: _currentIndex,
            destinations: _destinations,
            layout: layout,
            keyboardNavigation: profile.keyboardNavigation,
            onDestinationSelected: _selectDestination,
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

class _ShellDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  const _ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
}

class _WideShell extends StatelessWidget {
  final int currentIndex;
  final List<_ShellDestination> destinations;
  final ShellLayoutPolicy layout;
  final bool keyboardNavigation;
  final ValueChanged<int> onDestinationSelected;

  const _WideShell({
    required this.currentIndex,
    required this.destinations,
    required this.layout,
    required this.keyboardNavigation,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        NavigationRail(
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          extended: layout.railExtended,
          labelType: layout.railLabelType,
          minWidth: layout.railMinimumWidth,
          minExtendedWidth: layout.railMinimumExtendedWidth,
          destinations: destinations
              .map(
                (item) => NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                ),
              )
              .toList(growable: false),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(
            index: currentIndex,
            children: destinations.map((item) => item.page).toList(),
          ),
        ),
      ],
    );
    return Scaffold(
      body: keyboardNavigation
          ? FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: content,
            )
          : content,
    );
  }
}

class _MobileShellNavigationBar extends StatelessWidget {
  final int currentIndex;
  final double height;
  final int primaryDestinationIndex;
  final List<_ShellDestination> destinations;
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
  final _ShellDestination destination;
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
  final _ShellDestination destination;
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
