class LedgerBudget {
  final String id;
  final String periodType;
  final String periodKey;
  final String? categoryId;
  final String? categoryName;
  final double amount;
  final String currency;
  final double? alertThreshold;
  final String status;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LedgerBudget({
    required this.id,
    required this.periodType,
    required this.periodKey,
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    required this.currency,
    required this.alertThreshold,
    required this.status,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LedgerBudget.fromJson(Map<String, dynamic> json) {
    return LedgerBudget(
      id: json['id'] as String,
      periodType: json['period_type'] as String? ?? 'month',
      periodKey: json['period_key'] as String,
      categoryId: json['category_id'] as String?,
      categoryName: json['category_name'] as String?,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'CNY',
      alertThreshold: (json['alert_threshold'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'active',
      revision: (json['revision'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }

  bool get isOverall => categoryId == null;
}
