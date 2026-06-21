class LedgerTransaction {
  final String id;
  final String direction;
  final double amount;
  final String currency;
  final String? merchant;
  final String? note;
  final String? categoryId;
  final DateTime occurredAt;
  final String source;
  final DateTime createdAt;

  LedgerTransaction({
    required this.id,
    required this.direction,
    required this.amount,
    required this.currency,
    this.merchant,
    this.note,
    this.categoryId,
    required this.occurredAt,
    required this.source,
    required this.createdAt,
  });

  factory LedgerTransaction.fromJson(Map<String, dynamic> json) {
    return LedgerTransaction(
      id: json['id'] as String,
      direction: json['direction'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'CNY',
      merchant: json['merchant'] as String?,
      note: json['note'] as String?,
      categoryId: json['category_id'] as String?,
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      source: json['source'] as String? ?? 'manual',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'direction': direction,
    'amount': amount,
    'currency': currency,
    'merchant': merchant,
    'note': note,
    'category_id': categoryId,
  };

  bool get isExpense => direction == 'expense';
  bool get isIncome => direction == 'income';

  String get amountText =>
      '${isExpense ? '-' : '+'}¥${amount.toStringAsFixed(2)}';
}
