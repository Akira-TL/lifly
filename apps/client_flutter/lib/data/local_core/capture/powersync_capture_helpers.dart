part of 'powersync_capture_store.dart';

List<LocalCaptureAction> _parseLocalActions({
  required String text,
  required String captureId,
  required List<String> assetIds,
  required DateTime now,
}) {
  final actions = <LocalCaptureAction>[];
  final expense = _expenseAction(text, captureId, now);
  if (expense != null) actions.add(expense);
  final task = _taskAction(text, now);
  if (task != null) actions.add(task);
  final memo = _memoAction(text, captureId, assetIds, fallback: actions.isEmpty);
  if (memo != null) actions.add(memo);
  return actions;
}

LocalCaptureAction? _expenseAction(
  String text,
  String captureId,
  DateTime now,
) {
  final amountMatch = RegExp(
    r'(?:花了?|消费|支出)\s*(\d+(?:\.\d{1,2})?)|'
    r'(\d+(?:\.\d{1,2})?)\s*[元块]|'
    r'[¥￥](\d+(?:\.\d{1,2})?)|'
    r'(\d+(?:\.\d{1,2})?)\s*(?:的)?[^，,。；;！!]{0,12}(?:消费|支出|账单)',
  ).firstMatch(text);
  if (amountMatch == null) return null;
  final amountText = amountMatch.groups([1, 2, 3, 4]).whereType<String>().first;
  final amount = double.tryParse(amountText);
  if (amount == null || amount <= 0) return null;
  return LocalCaptureAction(
    type: 'expense_create',
    payload: {
      'amount': amount,
      'currency': 'CNY',
      'direction': 'expense',
      'merchant': _inferMerchant(text),
      'category_id': _inferCategoryId(text),
      'occurred_at': _inferExpenseOccurredAt(text, now).toIso8601String(),
      'source_capture_id': captureId,
    },
    confidence: 0.78,
    rawText: amountMatch.group(0),
  );
}

LocalCaptureAction? _taskAction(String text, DateTime now) {
  final match = RegExp(
    r'(?:提醒我|记得|别忘了|要做)\s*([^，,。；;！!\n]{2,40})',
  ).firstMatch(text);
  if (match == null) return null;
  final title = match.group(1)?.trim();
  if (title == null || title.isEmpty) return null;
  final remindAt = _inferTaskRemindAt(text, now);
  return LocalCaptureAction(
    type: 'task_create',
    payload: {
      'title': title,
      'remind_at': remindAt.toIso8601String(),
      'priority': _inferTaskPriority(text),
    },
    confidence: 0.80,
    rawText: title,
  );
}

LocalCaptureAction? _memoAction(
  String text,
  String captureId,
  List<String> assetIds, {
  required bool fallback,
}) {
  final hasMemoIntent = RegExp(r'(记录一下|记一下|备忘|日记)').hasMatch(text);
  if (!fallback && !hasMemoIntent && assetIds.isEmpty) return null;
  return LocalCaptureAction(
    type: 'memo_create',
    payload: {
      'type': hasMemoIntent && text.contains('日记') ? 'journal' : 'memo',
      'title': null,
      'content_markdown': text,
      'tags': ['capture'],
      'source_capture_id': captureId,
      if (assetIds.isNotEmpty) 'asset_ids': assetIds,
    },
    confidence: fallback ? 0.45 : 0.70,
    rawText: text,
  );
}

String _inferMerchant(String text) {
  final merchantKeywords = <String, String>{
    '食堂': '食堂',
    '超市': '超市',
    '支付宝': '支付宝',
    '微信': '微信',
    '地铁': '地铁',
    '滴滴': '滴滴出行',
    '咖啡': '咖啡',
    '奶茶': '奶茶',
  };
  for (final entry in merchantKeywords.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return '未知商户';
}

String _inferCategoryId(String text) {
  if (RegExp(r'(食堂|餐厅|饭|外卖|咖啡|奶茶)').hasMatch(text)) {
    return 'food';
  }
  if (RegExp(r'(公交|地铁|打车|滴滴)').hasMatch(text)) return 'transport';
  if (RegExp(r'(购物|买了|淘宝|天猫|超市)').hasMatch(text)) return 'shopping';
  return 'uncategorized';
}

DateTime _inferExpenseOccurredAt(String text, DateTime now) {
  final baseline = now.toUtc();
  if (text.contains('昨天')) return baseline.subtract(const Duration(days: 1));
  if (text.contains('前天')) return baseline.subtract(const Duration(days: 2));
  return baseline;
}

DateTime _inferTaskRemindAt(String text, DateTime now) {
  var target = now.toUtc();
  if (text.contains('明天')) {
    target = target.add(const Duration(days: 1));
  } else if (text.contains('后天')) {
    target = target.add(const Duration(days: 2));
  }
  var hour = 9;
  if (RegExp(r'(下午|晚些|今晚)').hasMatch(text)) hour = 15;
  if (RegExp(r'(晚上|今晚)').hasMatch(text)) hour = 20;
  if (RegExp(r'(中午)').hasMatch(text)) hour = 12;
  if (RegExp(r'(早上|明早)').hasMatch(text)) hour = 8;
  final explicitHour = RegExp(r'(\d{1,2})\s*点').firstMatch(text);
  if (explicitHour != null) {
    final parsed = int.tryParse(explicitHour.group(1) ?? '');
    if (parsed != null && parsed >= 0 && parsed <= 23) hour = parsed;
  }
  return DateTime.utc(target.year, target.month, target.day, hour);
}

String _inferTaskPriority(String text) {
  return RegExp(r'(紧急|必须|今天)').hasMatch(text) ? 'high' : 'normal';
}

List<int> _selectedIndexes(Map<String, Object?> input, int length) {
  final raw = input['selected_action_indexes'];
  if (raw == null) return List<int>.generate(length, (index) => index);
  if (raw is! List) return const [];
  final seen = <int>{};
  return raw.whereType<int>().where(seen.add).toList(growable: false);
}

String _readRequiredString(Map<String, Object?> input, String key) {
  final value = _readOptionalString(input, key);
  if (value == null) throw ArgumentError('$key is required');
  return value;
}

String? _readOptionalString(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _readStringList(Map<String, Object?> input, String key) {
  final value = input[key];
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

String _encodeAssetContext(List<LocalCaptureAssetContext> contexts) {
  return jsonEncode(
    contexts
        .map(
          (item) => {
            'asset_id': item.assetId,
            'kind': item.kind,
            'asset_type': item.assetType,
            'name': item.name,
            'mime_type': item.mimeType,
            'size_bytes': item.sizeBytes,
            'source_url': item.sourceUrl,
            'status': item.status,
            'extractor': item.extractor,
            'text': item.text,
            'error': item.error,
            'required_capability': item.requiredCapability,
          },
        )
        .toList(growable: false),
  );
}

List<LocalCaptureAssetContext> _decodeAssetContext(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) {
        final json = item.cast<String, Object?>();
        return LocalCaptureAssetContext(
          assetId: json['asset_id'] as String? ?? '',
          kind: json['kind'] as String?,
          assetType: json['asset_type'] as String?,
          name: json['name'] as String?,
          mimeType: json['mime_type'] as String?,
          sizeBytes: json['size_bytes'] as int?,
          sourceUrl: json['source_url'] as String?,
          status: json['status'] as String? ?? 'metadata_only',
          extractor: json['extractor'] as String? ?? 'metadata',
          text: json['text'] as String?,
          error: json['error'] as String?,
          requiredCapability: json['required_capability'] as String?,
        );
      })
      .toList(growable: false);
}

String _encodeActions(List<LocalCaptureAction> actions) {
  return jsonEncode(
    actions
        .map(
          (action) => {
            'type': action.type,
            'payload': action.payload,
            'confidence': action.confidence,
            'raw_text': action.rawText,
          },
        )
        .toList(),
  );
}

List<LocalCaptureAction> _decodeActions(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) {
        final json = item.cast<String, Object?>();
        return LocalCaptureAction(
          type: json['type'] as String? ?? 'memo_create',
          payload: (json['payload'] as Map?)?.cast<String, Object?>() ?? const {},
          confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
          rawText: json['raw_text'] as String?,
        );
      })
      .toList(growable: false);
}

String _encodeEntityRefs(List<LocalCoreEntityRef> refs) {
  return jsonEncode(
    refs.map((item) => {'type': item.type, 'id': item.id}).toList(),
  );
}

List<LocalCoreEntityRef> _decodeEntityRefs(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((item) {
        final json = item.cast<String, Object?>();
        return LocalCoreEntityRef(
          type: json['type'] as String? ?? 'unknown',
          id: json['id'] as String? ?? '',
        );
      })
      .toList(growable: false);
}

List<int> _decodeIntList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return decoded.whereType<int>().toList(growable: false);
}

List<String> _decodeStringList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const [];
  return decoded.whereType<String>().toList(growable: false);
}

DateTime _readRequiredDateTime(Object? value) {
  final parsed = _readDateTimeOrNull(value);
  if (parsed == null) {
    throw ArgumentError('Expected ISO datetime string, got $value');
  }
  return parsed;
}

DateTime? _readDateTimeOrNull(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.parse(value).toUtc();
  }
  return null;
}
