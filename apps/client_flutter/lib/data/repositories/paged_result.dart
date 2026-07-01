class PagedResult<T> {
  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  const PagedResult({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  int get nextOffset => offset + items.length;

  bool get hasMore => nextOffset < total;

  static PagedResult<T> fromData<T>(
    Map<String, dynamic> data,
    T Function(Map<String, dynamic> json) mapper,
  ) {
    final rawItems = data['items'] as List? ?? const [];
    return PagedResult<T>(
      items: rawItems.map((item) => mapper(item as Map<String, dynamic>)).toList(),
      total: _intValue(data['total']),
      limit: _intValue(data['limit']),
      offset: _intValue(data['offset']),
    );
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
