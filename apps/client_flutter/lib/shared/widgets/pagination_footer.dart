import 'package:flutter/material.dart';

class PaginationFooter extends StatelessWidget {
  final int total;
  final int current;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  const PaginationFooter({
    super.key,
    required this.total,
    required this.current,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: hasMore
            ? OutlinedButton(onPressed: onLoadMore, child: Text('加载更多（$current/$total）'))
            : Text('已显示 $current/$total', style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
