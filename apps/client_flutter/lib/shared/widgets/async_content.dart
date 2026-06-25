import 'package:flutter/material.dart';

typedef AsyncRefreshCallback = Future<void> Function();

class AsyncContentScaffold extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final bool isEmpty;
  final AsyncRefreshCallback onRefresh;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AsyncContentScaffold({
    super.key,
    required this.isLoading,
    required this.error,
    required this.isEmpty,
    required this.onRefresh,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.emptyIcon,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 96),
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return ErrorState(message: error!, onRetry: onRefresh);
    }
    if (isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: EmptyState(
          icon: emptyIcon,
          title: emptyTitle,
          subtitle: emptySubtitle,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: child,
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(icon, size: 64, color: theme.colorScheme.outline),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class ErrorState extends StatelessWidget {
  final String message;
  final AsyncRefreshCallback onRetry;

  const ErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
