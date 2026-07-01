import 'package:client_flutter/data/local_core/ledger/local_expense_mapper.dart';
import 'package:client_flutter/data/local_core/local_core_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalExpenseMapper maps row into LocalLedgerTransactionRecord', () {
    final tx = LocalExpenseMapper.fromRow({
      'id': 'tx_1',
      'direction': 'expense',
      'amount': 12.5,
      'currency': 'CNY',
      'merchant': 'Local Merchant',
      'note': 'local expense',
      'occurred_at': '2026-07-01T08:00:00.000Z',
      'status': 'active',
      'revision': 2,
      'created_at': '2026-07-01T08:00:00.000Z',
      'updated_at': '2026-07-01T09:00:00.000Z',
    });

    expect(tx.id, 'tx_1');
    expect(tx.amount, 12.5);
    expect(tx.revision, 2);
    expect(tx.occurredAt, DateTime.utc(2026, 7, 1, 8));
  });

  test('LocalExpenseMapper creates serializable snapshots', () {
    final tx = LocalLedgerTransactionRecord(
      id: 'tx_1',
      direction: 'expense',
      amount: 12.5,
      currency: 'CNY',
      merchant: 'Local Merchant',
      note: 'local expense',
      occurredAt: DateTime.utc(2026, 7, 1, 8),
      status: 'active',
      revision: 1,
      createdAt: DateTime.utc(2026, 7, 1, 8),
      updatedAt: DateTime.utc(2026, 7, 1, 8),
    );

    final snapshot = LocalExpenseMapper.snapshot(tx);

    expect(snapshot['id'], 'tx_1');
    expect(snapshot['amount'], 12.5);
    expect(snapshot['occurred_at'], '2026-07-01T08:00:00.000Z');
  });

  test('LocalExpenseCreateInput rejects non-positive amount', () {
    expect(
      () => LocalExpenseCreateInput.fromMap({'amount': 0}),
      throwsArgumentError,
    );
  });
}
