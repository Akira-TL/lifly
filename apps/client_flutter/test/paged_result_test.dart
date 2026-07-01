import 'package:client_flutter/data/repositories/paged_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PagedResult parses pagination metadata and hasMore', () {
    final page = PagedResult.fromData<int>(
      {
        'total': 3,
        'limit': 2,
        'offset': 0,
        'items': [
          {'value': 1},
          {'value': 2},
        ],
      },
      (json) => json['value'] as int,
    );

    expect(page.items, [1, 2]);
    expect(page.total, 3);
    expect(page.limit, 2);
    expect(page.offset, 0);
    expect(page.nextOffset, 2);
    expect(page.hasMore, isTrue);
  });

  test('PagedResult reports no more data on final page', () {
    final page = PagedResult.fromData<int>(
      {
        'total': 2,
        'limit': 2,
        'offset': 0,
        'items': [
          {'value': 1},
          {'value': 2},
        ],
      },
      (json) => json['value'] as int,
    );

    expect(page.hasMore, isFalse);
  });
}
