enum AiProviderKind {
  deterministic('deterministic'),
  ollama('ollama'),
  openAiCompatible('openai_compatible'),
  liflyCloud('lifly_cloud');

  const AiProviderKind(this.value);
  final String value;

  static AiProviderKind fromValue(String value) =>
      AiProviderKind.values.firstWhere(
        (item) => item.value == value,
        orElse: () => throw FormatException('Unknown AI provider kind: $value'),
      );
}

enum AiPrivacyBoundary {
  localDevice('local_device'),
  userEndpoint('user_endpoint'),
  cloudDisclosure('cloud_disclosure');

  const AiPrivacyBoundary(this.value);
  final String value;

  static AiPrivacyBoundary fromValue(String value) =>
      AiPrivacyBoundary.values.firstWhere(
        (item) => item.value == value,
        orElse: () =>
            throw FormatException('Unknown AI privacy boundary: $value'),
      );
}

enum AiProviderHealthState {
  healthy('healthy'),
  degraded('degraded'),
  unavailable('unavailable');

  const AiProviderHealthState(this.value);
  final String value;
}

class AiProviderConfig {
  const AiProviderConfig({
    required this.kind,
    required this.endpoint,
    required this.model,
    this.secretReference,
    required this.privacyBoundary,
    required this.dataLeavesDevice,
    this.timeout = const Duration(seconds: 30),
  });

  final AiProviderKind kind;
  final Uri endpoint;
  final String model;
  final String? secretReference;
  final AiPrivacyBoundary privacyBoundary;
  final bool dataLeavesDevice;
  final Duration timeout;

  Map<String, dynamic> toJson() => {
    'kind': kind.value,
    'endpoint': endpoint.toString(),
    'model': model,
    if (secretReference != null) 'secret_reference': secretReference,
    'privacy_boundary': privacyBoundary.value,
    'data_leaves_device': dataLeavesDevice,
    'timeout_seconds': timeout.inMilliseconds / 1000,
  };
}

class AiProviderCapabilities {
  const AiProviderCapabilities({
    this.structuredCandidateActions = true,
    this.actionTypes = const {
      'memo_create',
      'task_create',
      'expense_create',
      'asset_register_external_url',
    },
  });

  final bool structuredCandidateActions;
  final Set<String> actionTypes;
}

class AiProviderHealth {
  const AiProviderHealth({
    required this.provider,
    required this.model,
    required this.state,
    this.detail,
  });

  final AiProviderKind provider;
  final String model;
  final AiProviderHealthState state;
  final String? detail;
}

class AiContextItem {
  const AiContextItem({required this.dataType, required this.content});

  final String dataType;
  final String content;

  Map<String, dynamic> toJson() => {'data_type': dataType, 'content': content};

  factory AiContextItem.fromJson(Map<String, dynamic> json) {
    _expectOnlyKeys(json, const {'data_type', 'content'});
    return AiContextItem(
      dataType: _requiredString(json, 'data_type'),
      content: _requiredString(json, 'content'),
    );
  }
}

class AiPlanRequest {
  const AiPlanRequest({
    required this.text,
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
    this.context = const [],
  });

  final String text;
  final String timezone;
  final String locale;
  final List<AiContextItem> context;
}

class AiTokenUsage {
  const AiTokenUsage({this.inputTokens = 0, this.outputTokens = 0});

  final int inputTokens;
  final int outputTokens;
}

class AiProviderPlanResult {
  const AiProviderPlanResult({
    required this.provider,
    required this.model,
    required this.actions,
    this.usage = const AiTokenUsage(),
    this.fallbackUsed = false,
  });

  final AiProviderKind provider;
  final String model;
  final List<AiCandidateAction> actions;
  final AiTokenUsage usage;
  final bool fallbackUsed;
}

abstract interface class AiProvider {
  AiProviderConfig get config;

  AiProviderCapabilities capabilities();

  Future<AiProviderHealth> health();

  Future<AiProviderPlanResult> plan(AiPlanRequest request);
}

sealed class AiCandidateAction {
  const AiCandidateAction({required this.confidence, this.rawText});

  final double confidence;
  final String? rawText;

  String get type;
  Map<String, dynamic> get payloadJson;

  Map<String, dynamic> toJson() => {
    'type': type,
    'payload': payloadJson,
    'confidence': confidence,
    if (rawText != null) 'raw_text': rawText,
  };

  factory AiCandidateAction.fromJson(Map<String, dynamic> json) {
    _expectOnlyKeys(json, const {'type', 'payload', 'confidence', 'raw_text'});
    final type = _requiredString(json, 'type');
    final payload = _requiredMap(json, 'payload');
    final confidence = _requiredConfidence(json, 'confidence');
    final rawText = _optionalString(json['raw_text']);

    return switch (type) {
      'memo_create' => MemoCreateCandidateAction.fromPayload(
        payload,
        confidence: confidence,
        rawText: rawText,
      ),
      'task_create' => TaskCreateCandidateAction.fromPayload(
        payload,
        confidence: confidence,
        rawText: rawText,
      ),
      'expense_create' => ExpenseCreateCandidateAction.fromPayload(
        payload,
        confidence: confidence,
        rawText: rawText,
      ),
      'asset_register_external_url' =>
        AssetRegisterExternalUrlCandidateAction.fromPayload(
          payload,
          confidence: confidence,
          rawText: rawText,
        ),
      _ => throw FormatException('Unsupported AI candidate action: $type'),
    };
  }
}

final class MemoCreateCandidateAction extends AiCandidateAction {
  const MemoCreateCandidateAction({
    required this.memoType,
    required this.contentMarkdown,
    this.mood,
    required super.confidence,
    super.rawText,
  });

  factory MemoCreateCandidateAction.fromPayload(
    Map<String, dynamic> payload, {
    required double confidence,
    String? rawText,
  }) {
    _expectOnlyKeys(payload, const {'type', 'content_markdown', 'mood'});
    final memoType = _optionalString(payload['type']) ?? 'memo';
    if (memoType != 'memo' && memoType != 'journal') {
      throw FormatException('Unsupported memo type: $memoType');
    }
    return MemoCreateCandidateAction(
      memoType: memoType,
      contentMarkdown: _requiredString(payload, 'content_markdown'),
      mood: _optionalString(payload['mood']),
      confidence: confidence,
      rawText: rawText,
    );
  }

  @override
  String get type => 'memo_create';

  final String memoType;
  final String contentMarkdown;
  final String? mood;

  @override
  Map<String, dynamic> get payloadJson => {
    'type': memoType,
    'content_markdown': contentMarkdown,
    if (mood != null) 'mood': mood,
  };
}

final class TaskCreateCandidateAction extends AiCandidateAction {
  const TaskCreateCandidateAction({
    required this.title,
    this.remindAt,
    this.priority = 'normal',
    required super.confidence,
    super.rawText,
  });

  factory TaskCreateCandidateAction.fromPayload(
    Map<String, dynamic> payload, {
    required double confidence,
    String? rawText,
  }) {
    _expectOnlyKeys(payload, const {'title', 'remind_at', 'priority'});
    final priority = _optionalString(payload['priority']) ?? 'normal';
    if (!const {'low', 'normal', 'high', 'urgent'}.contains(priority)) {
      throw FormatException('Unsupported task priority: $priority');
    }
    return TaskCreateCandidateAction(
      title: _requiredString(payload, 'title'),
      remindAt: _optionalAwareDateTime(payload['remind_at'], 'remind_at'),
      priority: priority,
      confidence: confidence,
      rawText: rawText,
    );
  }

  @override
  String get type => 'task_create';

  final String title;
  final DateTime? remindAt;
  final String priority;

  @override
  Map<String, dynamic> get payloadJson => {
    'title': title,
    if (remindAt != null) 'remind_at': remindAt!.toUtc().toIso8601String(),
    'priority': priority,
  };
}

final class ExpenseCreateCandidateAction extends AiCandidateAction {
  const ExpenseCreateCandidateAction({
    required this.amount,
    this.currency = 'CNY',
    this.direction = 'expense',
    this.merchant = '未知商户',
    this.categoryHint,
    required this.occurredAt,
    required super.confidence,
    super.rawText,
  });

  factory ExpenseCreateCandidateAction.fromPayload(
    Map<String, dynamic> payload, {
    required double confidence,
    String? rawText,
  }) {
    _expectOnlyKeys(payload, const {
      'amount',
      'currency',
      'direction',
      'merchant',
      'category_hint',
      'occurred_at',
    });
    final amountValue = payload['amount'];
    if (amountValue is! num || amountValue <= 0) {
      throw const FormatException('Expected positive amount');
    }
    final direction = _optionalString(payload['direction']) ?? 'expense';
    if (direction != 'expense' && direction != 'income') {
      throw FormatException('Unsupported expense direction: $direction');
    }
    final currency = _optionalString(payload['currency']) ?? 'CNY';
    if (currency.length != 3) {
      throw const FormatException('Currency must be a 3-letter code');
    }
    return ExpenseCreateCandidateAction(
      amount: amountValue.toDouble(),
      currency: currency,
      direction: direction,
      merchant: _optionalString(payload['merchant']) ?? '未知商户',
      categoryHint: _optionalString(payload['category_hint']),
      occurredAt: _requiredAwareDateTime(payload, 'occurred_at'),
      confidence: confidence,
      rawText: rawText,
    );
  }

  @override
  String get type => 'expense_create';

  final double amount;
  final String currency;
  final String direction;
  final String merchant;
  final String? categoryHint;
  final DateTime occurredAt;

  @override
  Map<String, dynamic> get payloadJson => {
    'amount': amount,
    'currency': currency,
    'direction': direction,
    'merchant': merchant,
    if (categoryHint != null) 'category_hint': categoryHint,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };
}

final class AssetRegisterExternalUrlCandidateAction extends AiCandidateAction {
  const AssetRegisterExternalUrlCandidateAction({
    required this.externalUrl,
    this.title,
    required super.confidence,
    super.rawText,
  });

  factory AssetRegisterExternalUrlCandidateAction.fromPayload(
    Map<String, dynamic> payload, {
    required double confidence,
    String? rawText,
  }) {
    _expectOnlyKeys(payload, const {'external_url', 'title'});
    final externalUrl = Uri.tryParse(_requiredString(payload, 'external_url'));
    if (externalUrl == null ||
        !externalUrl.hasScheme ||
        !externalUrl.hasAuthority) {
      throw const FormatException('Expected absolute external_url');
    }
    return AssetRegisterExternalUrlCandidateAction(
      externalUrl: externalUrl,
      title: _optionalString(payload['title']),
      confidence: confidence,
      rawText: rawText,
    );
  }

  @override
  String get type => 'asset_register_external_url';

  final Uri externalUrl;
  final String? title;

  @override
  Map<String, dynamic> get payloadJson => {
    'external_url': externalUrl.toString(),
    if (title != null) 'title': title,
  };
}

void _expectOnlyKeys(Map<String, dynamic> json, Set<String> allowed) {
  final unexpected = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unexpected.isNotEmpty) {
    throw FormatException('Unexpected fields: ${unexpected.join(', ')}');
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string for $key');
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw const FormatException('Expected null or non-empty string');
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('Expected object for $key');
}

double _requiredConfidence(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num && value >= 0 && value <= 1) return value.toDouble();
  throw FormatException('Expected confidence in [0, 1] for $key');
}

DateTime _requiredAwareDateTime(Map<String, dynamic> json, String key) {
  final raw = _requiredString(json, key);
  return _parseAwareDateTime(raw, key);
}

DateTime? _optionalAwareDateTime(Object? value, String key) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected timezone-aware datetime for $key');
  }
  return _parseAwareDateTime(value, key);
}

DateTime _parseAwareDateTime(String raw, String key) {
  final hasTimezone =
      raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
  if (!hasTimezone) {
    throw FormatException('Expected timezone-aware datetime for $key');
  }
  return DateTime.parse(raw).toUtc();
}
