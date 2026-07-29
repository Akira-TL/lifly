import 'package:client_flutter/app/shell/shell_layout_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class ShellDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;

  const ShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });
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
  bool isEnabled(T intent) => !_hasEditableTextFocus();

  @override
  Object? invoke(T intent) {
    onInvoke();
    return null;
  }
}

bool _hasEditableTextFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
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
  final VoidCallback onToggleSidebar;

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
    required this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extended = layout.railExtended && !sidebarCollapsed;
    final content = Row(
      children: [
        _WebNavigationPanel(
          currentIndex: currentIndex,
          destinations: destinations,
          extended: extended,
          layout: layout,
          onDestinationSelected: onDestinationSelected,
          onQuickCapture: onQuickCapture,
          onOpenSearch: onOpenSearch,
          onOpenManagement: onOpenManagement,
          onToggleSidebar: onToggleSidebar,
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        Expanded(
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
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

class _WebNavigationPanel extends StatelessWidget {
  final int currentIndex;
  final List<ShellDestination> destinations;
  final bool extended;
  final ShellLayoutPolicy layout;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onQuickCapture;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenManagement;
  final VoidCallback onToggleSidebar;

  const _WebNavigationPanel({
    required this.currentIndex,
    required this.destinations,
    required this.extended,
    required this.layout,
    required this.onDestinationSelected,
    required this.onQuickCapture,
    required this.onOpenSearch,
    required this.onOpenManagement,
    required this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: NavigationRail(
        key: const Key('web_primary_navigation'),
        selectedIndex: currentIndex,
        onDestinationSelected: onDestinationSelected,
        extended: extended,
        useIndicator: true,
        backgroundColor: Colors.transparent,
        groupAlignment: -0.55,
        labelType: extended
            ? NavigationRailLabelType.none
            : layout.railLabelType,
        minWidth: layout.railMinimumWidth,
        minExtendedWidth: 248,
        leading: _WebNavigationLeading(
          extended: extended,
          onOpenSearch: onOpenSearch,
          onQuickCapture: onQuickCapture,
        ),
        trailing: _WebNavigationTrailing(
          extended: extended,
          onOpenManagement: onOpenManagement,
          onToggleSidebar: layout.railExtended ? onToggleSidebar : null,
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

class _WebNavigationLeading extends StatelessWidget {
  final bool extended;
  final VoidCallback onOpenSearch;
  final VoidCallback onQuickCapture;

  const _WebNavigationLeading({
    required this.extended,
    required this.onOpenSearch,
    required this.onQuickCapture,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extended ? 216 : 56,
      child: Column(
        children: [
          _LiflyBrand(extended: extended),
          const SizedBox(height: 20),
          _SidebarActionButton(
            extended: extended,
            icon: Icons.search,
            label: '搜索',
            shortcut: 'Ctrl K',
            tooltip: '全局搜索 · Ctrl+K',
            onPressed: onOpenSearch,
          ),
          const SizedBox(height: 8),
          _SidebarActionButton(
            extended: extended,
            icon: Icons.auto_awesome,
            label: '快速记录',
            shortcut: 'Ctrl N',
            tooltip: 'AI 快速记录 · Ctrl+N',
            emphasized: true,
            onPressed: onQuickCapture,
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _WebNavigationTrailing extends StatelessWidget {
  final bool extended;
  final VoidCallback onOpenManagement;
  final VoidCallback? onToggleSidebar;

  const _WebNavigationTrailing({
    required this.extended,
    required this.onOpenManagement,
    required this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extended ? 216 : 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          _SidebarActionButton(
            extended: extended,
            icon: Icons.dashboard_customize_outlined,
            label: '管理',
            tooltip: '管理中心',
            onPressed: onOpenManagement,
          ),
          if (onToggleSidebar != null) ...[
            const SizedBox(height: 4),
            _SidebarActionButton(
              extended: extended,
              icon: extended
                  ? Icons.keyboard_double_arrow_left
                  : Icons.keyboard_double_arrow_right,
              label: '收起侧栏',
              tooltip: extended ? '收起侧栏' : '展开侧栏',
              onPressed: onToggleSidebar!,
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _LiflyBrand extends StatelessWidget {
  final bool extended;

  const _LiflyBrand({required this.extended});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      label: 'Lifly',
      child: Row(
        mainAxisAlignment: extended
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              'L',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (extended) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lifly',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '生活数据中心',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarActionButton extends StatelessWidget {
  final bool extended;
  final IconData icon;
  final String label;
  final String tooltip;
  final String? shortcut;
  final bool emphasized;
  final VoidCallback onPressed;

  const _SidebarActionButton({
    required this.extended,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.shortcut,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!extended) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }

    final button = emphasized
        ? FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: _SidebarActionLabel(label: label, shortcut: shortcut),
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: _SidebarActionLabel(label: label, shortcut: shortcut),
          );
    return SizedBox(width: double.infinity, child: button);
  }
}

class _SidebarActionLabel extends StatelessWidget {
  final String label;
  final String? shortcut;

  const _SidebarActionLabel({required this.label, this.shortcut});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, textAlign: TextAlign.left)),
        if (shortcut != null)
          Text(
            shortcut!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
