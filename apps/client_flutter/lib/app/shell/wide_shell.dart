import 'package:client_flutter/app/shell/shell_layout_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class ShellDestination {
  final String label;
  final String? webLabel;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  const ShellDestination({
    required this.label,
    this.webLabel,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  String get dashboardLabel => webLabel ?? label;
}

class _OpenSearchIntent extends Intent {
  const _OpenSearchIntent();
}

class _QuickCaptureIntent extends Intent {
  const _QuickCaptureIntent();
}

class _EditableAwareAction<T extends Intent> extends Action<T> {
  final VoidCallback onInvoke;

  _EditableAwareAction(this.onInvoke);

  @override
  bool isEnabled(T intent) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext == null || !_isEditableContext(focusContext);
  }

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}

bool _isEditableContext(BuildContext context) {
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}

class WideShell extends StatelessWidget {
  static const _maximumContentWidth = 1600.0;

  final int currentIndex;
  final List<ShellDestination> destinations;
  final ShellLayoutPolicy layout;
  final bool keyboardNavigation;
  final bool sidebarCollapsed;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onQuickCapture;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenManagement;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleSidebar;
  final String accountLabel;
  final String accountSubtitle;

  const WideShell({
    super.key,
    required this.currentIndex,
    required this.destinations,
    required this.layout,
    required this.keyboardNavigation,
    required this.sidebarCollapsed,
    required this.onDestinationSelected,
    required this.onQuickCapture,
    required this.onOpenSearch,
    required this.onOpenManagement,
    required this.onOpenSettings,
    required this.onToggleSidebar,
    required this.accountLabel,
    required this.accountSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dashboard = layout.railExtended;
    final content = Row(
      children: [
        if (dashboard)
          _DashboardSidebar(
            currentIndex: currentIndex,
            destinations: destinations,
            collapsed: sidebarCollapsed,
            onDestinationSelected: onDestinationSelected,
            onQuickCapture: onQuickCapture,
            onOpenManagement: onOpenManagement,
            onOpenSettings: onOpenSettings,
            onToggleSidebar: onToggleSidebar,
            accountLabel: accountLabel,
            accountSubtitle: accountSubtitle,
          )
        else
          _CompactNavigationRail(
            currentIndex: currentIndex,
            destinations: destinations,
            layout: layout,
            onDestinationSelected: onDestinationSelected,
            onQuickCapture: onQuickCapture,
            onOpenSearch: onOpenSearch,
            onOpenManagement: onOpenManagement,
            onOpenSettings: onOpenSettings,
          ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        Expanded(
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth
                    .clamp(0, _maximumContentWidth)
                    .toDouble();
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: IndexedStack(
                      index: currentIndex,
                      children: destinations
                          .map((item) => item.page)
                          .toList(growable: false),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );

    final shortcuts = Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _OpenSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _QuickCaptureIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenSearchIntent: _EditableAwareAction<_OpenSearchIntent>(
            onOpenSearch,
          ),
          _QuickCaptureIntent: _EditableAwareAction<_QuickCaptureIntent>(
            onQuickCapture,
          ),
        },
        child: Focus(autofocus: keyboardNavigation, child: content),
      ),
    );

    return Scaffold(
      body: keyboardNavigation
          ? FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: shortcuts,
            )
          : shortcuts,
    );
  }
}

class _DashboardSidebar extends StatelessWidget {
  static const expandedWidth = 218.0;
  static const collapsedWidth = 64.0;

  final int currentIndex;
  final List<ShellDestination> destinations;
  final bool collapsed;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onQuickCapture;
  final VoidCallback onOpenManagement;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleSidebar;
  final String accountLabel;
  final String accountSubtitle;

  const _DashboardSidebar({
    required this.currentIndex,
    required this.destinations,
    required this.collapsed,
    required this.onDestinationSelected,
    required this.onQuickCapture,
    required this.onOpenManagement,
    required this.onOpenSettings,
    required this.onToggleSidebar,
    required this.accountLabel,
    required this.accountSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      key: const Key('web_primary_navigation'),
      width: collapsed ? collapsedWidth : expandedWidth,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      color: theme.colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        collapsed ? 9 : 15,
        22,
        collapsed ? 9 : 15,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashboardBrand(collapsed: collapsed),
          const SizedBox(height: 18),
          _CaptureButton(collapsed: collapsed, onPressed: onQuickCapture),
          const SizedBox(height: 18),
          if (!collapsed) const _SidebarGroupLabel('核心'),
          _DashboardNavigation(
            currentIndex: currentIndex,
            destinations: destinations,
            collapsed: collapsed,
            onDestinationSelected: onDestinationSelected,
          ),
          const SizedBox(height: 16),
          if (!collapsed) const _SidebarGroupLabel('管理'),
          _SidebarItem(
            icon: Icons.grid_view_outlined,
            label: '全部内容',
            collapsed: collapsed,
            onPressed: onOpenManagement,
          ),
          _SidebarItem(
            icon: Icons.settings_outlined,
            label: '设置',
            collapsed: collapsed,
            onPressed: onOpenSettings,
          ),
          const Spacer(),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 10),
          _SidebarFooter(
            collapsed: collapsed,
            onToggleSidebar: onToggleSidebar,
            accountLabel: accountLabel,
            accountSubtitle: accountSubtitle,
          ),
        ],
      ),
    );
  }
}

class _DashboardBrand extends StatelessWidget {
  final bool collapsed;

  const _DashboardBrand({required this.collapsed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: collapsed
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          _LiflyMark(size: 30),
          if (!collapsed) ...[
            const SizedBox(width: 10),
            Text(
              'Lifly',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiflyMark extends StatelessWidget {
  final double size;

  const _LiflyMark({required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -0.31,
            child: Container(
              width: size * 0.2,
              height: size * 0.62,
              decoration: BoxDecoration(
                color: theme.colorScheme.onPrimary,
                borderRadius: BorderRadius.circular(size),
              ),
            ),
          ),
          Positioned(
            left: size * 0.47,
            top: size * 0.57,
            child: Transform.rotate(
              angle: -0.31,
              child: Container(
                width: size * 0.34,
                height: size * 0.18,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onPrimary,
                  borderRadius: BorderRadius.circular(size),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onPressed;

  const _CaptureButton({required this.collapsed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        key: const Key('web_quick_capture'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 40,
          child: collapsed
              ? Icon(Icons.add, color: theme.colorScheme.onPrimary, size: 20)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '快速记录',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Ctrl N',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.72,
                          ),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
    return collapsed ? Tooltip(message: '快速记录 · Ctrl+N', child: child) : child;
  }
}

class _SidebarGroupLabel extends StatelessWidget {
  final String label;

  const _SidebarGroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 7),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _DashboardNavigation extends StatelessWidget {
  final int currentIndex;
  final List<ShellDestination> destinations;
  final bool collapsed;
  final ValueChanged<int> onDestinationSelected;

  const _DashboardNavigation({
    required this.currentIndex,
    required this.destinations,
    required this.collapsed,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < destinations.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _SidebarItem(
              key: Key('web_destination_${destinations[index].label}'),
              icon: currentIndex == index
                  ? destinations[index].selectedIcon
                  : destinations[index].icon,
              label: destinations[index].dashboardLabel,
              selected: currentIndex == index,
              collapsed: collapsed,
              onPressed: () => onDestinationSelected(index),
            ),
          ),
      ],
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onPressed;

  const _SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.collapsed,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    final item = Material(
      color: selected
          ? theme.colorScheme.surfaceContainerHigh
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 39,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: Container(width: 2, color: theme.colorScheme.primary),
                ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
                child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: foreground),
                    if (!collapsed) ...[
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: foreground,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return collapsed ? Tooltip(message: label, child: item) : item;
  }
}

class _SidebarFooter extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onToggleSidebar;
  final String accountLabel;
  final String accountSubtitle;

  const _SidebarFooter({
    required this.collapsed,
    required this.onToggleSidebar,
    required this.accountLabel,
    required this.accountSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (collapsed) {
      return IconButton(
        tooltip: '展开侧栏',
        onPressed: onToggleSidebar,
        icon: const Icon(Icons.keyboard_double_arrow_right, size: 18),
      );
    }
    return Row(
      children: [
        Container(
          width: 29,
          height: 29,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface,
            shape: BoxShape.circle,
          ),
          child: Text(
            'L',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.surface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                accountLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                accountSubtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '收起侧栏',
          onPressed: onToggleSidebar,
          icon: const Icon(Icons.keyboard_double_arrow_left, size: 18),
        ),
      ],
    );
  }
}

class _CompactNavigationRail extends StatelessWidget {
  final int currentIndex;
  final List<ShellDestination> destinations;
  final ShellLayoutPolicy layout;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onQuickCapture;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenManagement;
  final VoidCallback onOpenSettings;

  const _CompactNavigationRail({
    required this.currentIndex,
    required this.destinations,
    required this.layout,
    required this.onDestinationSelected,
    required this.onQuickCapture,
    required this.onOpenSearch,
    required this.onOpenManagement,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: NavigationRail(
        key: const Key('compact_primary_navigation'),
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        extended: false,
        useIndicator: true,
        backgroundColor: Colors.transparent,
        groupAlignment: -0.42,
        labelType: layout.railLabelType,
        minWidth: layout.railMinimumWidth,
        leading: Column(
          children: [
            const _LiflyMark(size: 34),
            const SizedBox(height: 14),
            IconButton(
              tooltip: '全局搜索 · Ctrl+K',
              onPressed: onOpenSearch,
              icon: const Icon(Icons.search),
            ),
            IconButton.filledTonal(
              tooltip: '快速记录 · Ctrl+N',
              onPressed: onQuickCapture,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '管理中心',
              onPressed: onOpenManagement,
              icon: const Icon(Icons.grid_view_outlined),
            ),
            IconButton(
              tooltip: '设置',
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
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
    );
  }
}
