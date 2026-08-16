import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';

class CloudAiDisclosureScope {
  CloudAiDisclosureScope({
    required this.consentId,
    required this.granted,
    required this.provider,
    required this.model,
    required Set<String> allowedDataTypes,
    required this.reason,
    required this.includesAttachments,
    required this.includesHistory,
  }) : allowedDataTypes = Set.unmodifiable(allowedDataTypes) {
    if (consentId.isEmpty) throw ArgumentError.value(consentId, 'consentId');
    if (model.isEmpty) throw ArgumentError.value(model, 'model');
    if (this.allowedDataTypes.isEmpty) {
      throw ArgumentError.value(allowedDataTypes, 'allowedDataTypes');
    }
    if (reason.isEmpty) throw ArgumentError.value(reason, 'reason');
  }

  final String consentId;
  final bool granted;
  final AiProviderKind provider;
  final String model;
  final Set<String> allowedDataTypes;
  final String reason;
  final bool includesAttachments;
  final bool includesHistory;

  Map<String, dynamic> toJson() => {
    'consent_id': consentId,
    'mode': 'once',
    'granted': granted,
    'destination': 'lifly_cloud_ai',
    'provider': provider.value,
    'model': model,
    'allowed_data_types': allowedDataTypes.toList(growable: false),
    'reason': reason,
    'includes_attachments': includesAttachments,
    'includes_history': includesHistory,
  };
}

class CloudAiInferenceRequest {
  const CloudAiInferenceRequest({
    required this.requestId,
    required this.disclosure,
    required this.input,
    this.context = const [],
    this.history = const [],
    this.attachments = const [],
    this.timezone = 'Asia/Shanghai',
    this.locale = 'zh-CN',
  });

  final String requestId;
  final CloudAiDisclosureScope disclosure;
  final AiContextItem input;
  final List<AiContextItem> context;
  final List<AiContextItem> history;
  final List<AiContextItem> attachments;
  final String timezone;
  final String locale;

  CloudAiInferenceRequest copyWith({
    String? requestId,
    CloudAiDisclosureScope? disclosure,
    AiContextItem? input,
    List<AiContextItem>? context,
    List<AiContextItem>? history,
    List<AiContextItem>? attachments,
    String? timezone,
    String? locale,
  }) {
    return CloudAiInferenceRequest(
      requestId: requestId ?? this.requestId,
      disclosure: disclosure ?? this.disclosure,
      input: input ?? this.input,
      context: context ?? this.context,
      history: history ?? this.history,
      attachments: attachments ?? this.attachments,
      timezone: timezone ?? this.timezone,
      locale: locale ?? this.locale,
    );
  }

  void validateForSend() {
    if (requestId.isEmpty) throw StateError('云端 AI 请求编号不能为空');
    if (!disclosure.granted) {
      throw StateError('使用云端 AI 前必须进行本次明确授权');
    }
    if (history.isNotEmpty && !disclosure.includesHistory) {
      throw StateError('本次未授权向云端 AI 提供历史会话');
    }
    if (attachments.isNotEmpty && !disclosure.includesAttachments) {
      throw StateError('本次未授权向云端 AI 提供附件');
    }

    final disclosedItems = [input, ...context, ...history, ...attachments];
    for (final item in disclosedItems) {
      if (!disclosure.allowedDataTypes.contains(item.dataType)) {
        throw StateError('数据类型 ${item.dataType} 不在本次云端 AI 授权范围内');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'disclosure': disclosure.toJson(),
    'input': input.toJson(),
    'context': context.map((item) => item.toJson()).toList(growable: false),
    'history': history.map((item) => item.toJson()).toList(growable: false),
    'attachments': attachments
        .map((item) => item.toJson())
        .toList(growable: false),
    'timezone': timezone,
    'locale': locale,
  };
}

class CloudAiInferenceResponse {
  const CloudAiInferenceResponse({
    required this.requestId,
    required this.provider,
    required this.model,
    required this.actions,
  });

  final String requestId;
  final AiProviderKind provider;
  final String model;
  final List<AiCandidateAction> actions;

  factory CloudAiInferenceResponse.fromJson(Map<String, dynamic> json) {
    _expectOnlyKeys(json, const {'request_id', 'provider', 'model', 'actions'});
    final rawActions = json['actions'];
    if (rawActions is! List) {
      throw const FormatException('云端 AI 返回的候选动作列表格式无效');
    }
    return CloudAiInferenceResponse(
      requestId: _requiredString(json, 'request_id'),
      provider: AiProviderKind.fromValue(_requiredString(json, 'provider')),
      model: _requiredString(json, 'model'),
      actions: rawActions
          .map((item) {
            if (item is! Map) {
              throw const FormatException('云端 AI 返回的候选动作格式无效');
            }
            return AiCandidateAction.fromJson(Map<String, dynamic>.from(item));
          })
          .toList(growable: false),
    );
  }
}

extension AiCandidateActionCaptureAdapter on AiCandidateAction {
  AiCaptureAction toCaptureAction() => AiCaptureAction.fromJson(toJson());
}

void _expectOnlyKeys(Map<String, dynamic> json, Set<String> allowed) {
  final unexpected = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unexpected.isNotEmpty) {
    throw FormatException('云端 AI 返回了未授权字段：${unexpected.join(', ')}');
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Expected non-empty string for $key');
}
