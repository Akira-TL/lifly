import 'package:client_flutter/data/local_core/local_core_models.dart';

class LocalExpenseCreateInput {
  final String direction;
  final double amount;
  final String currency;
  final String? merchant;
  final String? note;
  final DateTime? occurredAt;

  const LocalExpenseCreateInput({
    required this.direction,
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.note,
    required this.occurredAt,
  });

  factory LocalExpenseCreateInput.fromMap(Map<String, Object?> input) {
    final amount = _readPositiveAmount(input, 'amount');
    return LocalExpenseCreateInput(
      direction: _readOptionalString(input, 'direction') ?? 'expense',
      amount: amount,
      currency: _readOptionalString(input, 'currency') ?? 'CNY',
      merchant: _readOptionalString(input, 'merchant'),
      note: _readOptionalString(input, 'note'),
      occurredAt: _readOptionalDateTime(input, 'occurred_at'),
    );
  }
}

class LocalExpenseSearchInput {
  final String query;
  final int limit;

  const LocalExpenseSearchInput({required this.query, required this.limit});

  factory LocalExpenseSearchInput.fromMap(Map<String, Object?> input) {
    return LocalExpenseSearchInput(
      query: (_readOptionalString(input, 'q') ?? '').toLowerCase(),
      limit: _readPositiveInt(input, 'limit', defaultValue: 20, maxValue: 100),
    );
  }
}

class LocalExpenseSummaryInput {
  final String period;

  const LocalExpenseSummaryInput({required this.period});

  factory LocalExpenseSummaryInput.fromMap(Map<String, Object?> input) {
    return LocalExpenseSummaryInput(
      period: _readOptionalString(input, 'period') ?? 'current_month',
    );
  }
}

class LocalExpenseDeleteInput {
  final String transactionId;
  final String status;

  const LocalExpenseDeleteInput({
    required this.transactionId,
    required this.status,
  });

  factory LocalExpenseDeleteInput.fromMap(Map<String, Object?> input) {
    return LocalExpenseDeleteInput(
      transactionId: _readTransactionId(input),
      status: _readOptionalString(input, 'status') ?? 'deleted',
    );
  }
}

class LocalExpenseMapper {
  const LocalExpenseMapper._();

  static LocalLedgerTransactionRecord fromRow(Map<String, Object?> row) {
    return LocalLedgerTransactionRecord(
      id: row['id'] as String,
      direction: row['direction'] as String? ?? 'expense',
      amount: (row['amount'] as num).toDouble(),
      currency: row['currency'] as String? ?? 'CNY',
      merchant: row['merchant'] as String?,
      note: row['note'] as String?,
      occurredAt: _readDateTime(row['occurred_at']),
      status: row['status'] as String? ?? 'active',
      revision: row['revision'] as int? ?? 1,
      createdAt: _readDateTime(row['created_at']),
      updatedAt: _readDateTime(row['updated_at']),
    );
  }

  static Map<String, Object?> snapshot(LocalLedgerTransactionRecord tx) {
    return {
      'id': tx.id,
      'direction': tx.direction,
      'amount': tx.amount,
      'currency': tx.currency,
      'merchant': tx.merchant,
      'note': tx.note,
      'occurred_at': tx.occurredAt.toIso8601String(),
      'status': tx.status,
      'revision': tx.revision,
      'created_at': tx.createdAt.toIso8601String(),
      'updated_at': tx.updatedAt.toIso8601String(),
    };
  }
}

String _readTransactionId(Map<String, Object?> input) {
  final transactionId =
      _readOptionalString(input, 'transaction_id') ??
      _readOptionalString(input, 'expense_id') ??
      _readOptionalString(input, 'id');
  if (transactionId == null) {
    throw ArgumentError('transaction_id is required');
  }
  return transactionId;
}

String? _readOptionalString(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is! String) return null;
  return value.trim().isEmpty ? null : value.trim();
}

double _readPositiveAmount(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value is! num) {
    throw ArgumentError('$key is required');
  }
  final amount = value.toDouble();
  if (amount <= 0) {
    throw ArgumentError('$key must be greater than 0');
  }
  return amount;
}

DateTime? _readOptionalDateTime(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value).toUtc();
  }
  return null;
}

DateTime _readDateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.parse(value).toUtc();
  throw ArgumentError('Expected ISO datetime string, got $value');
}

int _readPositiveInt(
  Map<String, Object?> input,
  String key, {
  required int defaultValue,
  required int maxValue,
}) {
  final value = input[key];
  if (value is! int || value <= 0) return defaultValue;
  return value > maxValue ? maxValue : value;
}
