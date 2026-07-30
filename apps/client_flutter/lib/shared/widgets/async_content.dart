import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AsyncRefreshCallback = Future<void> Function();

class AsyncContentScaffold extends StatelessWidget {
  final bool isLoading;
  final bool isOffline;
  final String? error;
  final bool isEmpty;
  final AsyncRefreshCallback onRefresh;
  final String loadingMessage;
  final String offlineTitle;
  final String offlineMessage;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AsyncContentScaffold({
    super.key,
    required this.isLoading,
    this.isOffline = false,
    required this.error,
    required this.isEmpty,
    required this.onRefresh,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.child,
    this.loadingMessage = '正在加载',
    this.offlineTitle = '当前离线',
    this.offlineMessage = '已有本地数据仍可使用，需要联网的操作将在连接恢复后可用。',
    this.emptyActionLabel,
    this.onEmptyAction,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 96),
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return LoadingState(message: loadingMessage, padding: padding);
    }
    if (isOffline) {
      return OfflineState(
        title: offlineTitle,
        message: offlineMessage,
        onRetry: onRefresh,
        padding: padding,
      );
    }
    if (error != null) {
      return ErrorState(message: error!, onRetry: onRefresh, padding: padding);
    }
    if (isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          subtitle: emptySubtitle,
          actionLabel: emptyActionLabel,
          onAction: onEmptyAction,
          padding: padding,
        ),
      );
    }
    return RefreshIndicator(onRefresh: onRefresh, child: child);
  }
}

class LoadingState extends StatelessWidget {
  final String message;
  final EdgeInsetsGeometry padding;

  const LoadingState({
    super.key,
    this.message = '正在加载',
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('page_state_loading'),
      label: message,
      liveRegion: true,
      child: _PageStateViewport(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$title。$subtitle',
      child: _PageStateViewport(
        padding: padding,
        child: _PageStateContent(
          icon: icon,
          iconColor: Theme.of(context).colorScheme.outline,
          title: title,
          message: subtitle,
          action: onAction == null || actionLabel == null
              ? null
              : FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add),
                  label: Text(actionLabel!),
                ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final AsyncRefreshCallback onRetry;
  final EdgeInsetsGeometry padding;

  const ErrorState({
    super.key,
    this.title = '加载失败',
    required this.message,
    required this.onRetry,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$title。$message',
      liveRegion: true,
      child: _PageStateViewport(
        padding: padding,
        child: _PageStateContent(
          icon: Icons.error_outline,
          iconColor: theme.colorScheme.error,
          title: title,
          message: message,
          selectableMessage: true,
          action: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              OutlinedButton.icon(
                key: const Key('copy_error_diagnostics'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('诊断信息已复制')));
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制诊断'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OfflineState extends StatelessWidget {
  final String title;
  final String message;
  final AsyncRefreshCallback? onRetry;
  final EdgeInsetsGeometry padding;

  const OfflineState({
    super.key,
    this.title = '当前离线',
    this.message = '已有本地数据仍可使用，需要联网的操作将在连接恢复后可用。',
    this.onRetry,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$title。$message',
      liveRegion: true,
      child: _PageStateViewport(
        padding: padding,
        child: _PageStateContent(
          icon: Icons.cloud_off_outlined,
          iconColor: theme.colorScheme.tertiary,
          title: title,
          message: message,
          action: onRetry == null
              ? null
              : OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('重新连接'),
                ),
        ),
      ),
    );
  }
}

class _PageStateViewport extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _PageStateViewport({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minimumHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumHeight),
            child: Center(
              child: ConstrainedBox(
                key: const Key('page_state_content'),
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageStateContent extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final Widget? action;
  final bool selectableMessage;

  const _PageStateContent({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.action,
    this.selectableMessage = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: iconColor),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (selectableMessage)
          SelectableText(
            message,
            textAlign: TextAlign.left,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          )
        else
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    );
  }
}
