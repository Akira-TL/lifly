import 'package:client_flutter/data/local_core/local_core_models.dart';

class LocalMemoClassificationSuggestion {
  final String tag;
  final double confidence;
  final String reason;

  const LocalMemoClassificationSuggestion({
    required this.tag,
    required this.confidence,
    required this.reason,
  });
}

class LocalTagRule {
  final String tag;
  final String colorToken;
  final String iconToken;
  final int sortOrder;
  final List<String> keywords;
  final String reason;

  const LocalTagRule({
    required this.tag,
    required this.colorToken,
    required this.iconToken,
    required this.sortOrder,
    required this.keywords,
    required this.reason,
  });
}

class LocalMemoClassificationEngine {
  static const rules = <LocalTagRule>[
    LocalTagRule(
      tag: '清单',
      colorToken: 'green',
      iconToken: 'checklist',
      sortOrder: 10,
      keywords: ['清单', '准备', '采购', '买', '装备', '待办', '事项', 'checklist', 'todo'],
      reason: '内容包含清单、准备或采购语义。',
    ),
    LocalTagRule(
      tag: '读书',
      colorToken: 'blue',
      iconToken: 'book',
      sortOrder: 20,
      keywords: ['读书', '书摘', '读后感', '摘录', '章节', '作者', '阅读', '《', '》'],
      reason: '内容包含阅读、书籍或摘录语义。',
    ),
    LocalTagRule(
      tag: '工作',
      colorToken: 'orange',
      iconToken: 'briefcase',
      sortOrder: 30,
      keywords: ['项目', '会议', '复盘', '需求', '开发', 'PR', '评审', '排期', '周报', '文档'],
      reason: '内容包含工作、项目或协作语义。',
    ),
    LocalTagRule(
      tag: '旅行',
      colorToken: 'purple',
      iconToken: 'map',
      sortOrder: 40,
      keywords: ['旅行', '出行', '行程', '机票', '酒店', '露营', '路线', '签证', '周末游'],
      reason: '内容包含旅行、出行或路线安排语义。',
    ),
    LocalTagRule(
      tag: '健康',
      colorToken: 'cyan',
      iconToken: 'health',
      sortOrder: 50,
      keywords: ['健身', '跑步', '体重', '睡眠', '体检', '运动', '饮食', '训练', '健康'],
      reason: '内容包含健康、运动或身体状态语义。',
    ),
    LocalTagRule(
      tag: '财务',
      colorToken: 'teal',
      iconToken: 'wallet',
      sortOrder: 60,
      keywords: ['账单', '消费', '预算', '发票', '报销', '收入', '支出', '流水', '付款'],
      reason: '内容包含账单、预算或收支语义。',
    ),
    LocalTagRule(
      tag: '灵感',
      colorToken: 'violet',
      iconToken: 'sparkles',
      sortOrder: 70,
      keywords: ['想法', '灵感', '方案', '脑暴', '构思', '创意', 'idea'],
      reason: '内容包含想法、方案或创意语义。',
    ),
    LocalTagRule(
      tag: '生活',
      colorToken: 'gray',
      iconToken: 'home',
      sortOrder: 90,
      keywords: ['家庭', '生活', '购物', '整理', '家里', '日常', '朋友', '周末'],
      reason: '内容包含生活、家庭或日常记录语义。',
    ),
  ];

  const LocalMemoClassificationEngine();

  List<LocalMemoClassificationSuggestion> classify(LocalMemoRecord memo) {
    final text = [
      memo.title ?? '',
      memo.contentMarkdown,
      memo.tags.join(' '),
    ].join('\n').toLowerCase();
    final suggestions = <String, LocalMemoClassificationSuggestion>{};
    for (final rule in rules) {
      final hitCount = rule.keywords
          .where((keyword) => text.contains(keyword.toLowerCase()))
          .length;
      if (hitCount == 0) continue;
      var confidence = (0.58 + hitCount * 0.08).clamp(0.0, 0.92);
      if (rule.tag == '清单' && _looksLikeList(memo.contentMarkdown)) {
        confidence = confidence < 0.86 ? 0.86 : confidence;
      }
      if (rule.tag == '读书' && text.contains('《') && text.contains('》')) {
        confidence = confidence < 0.88 ? 0.88 : confidence;
      }
      suggestions[rule.tag] = LocalMemoClassificationSuggestion(
        tag: rule.tag,
        confidence: confidence,
        reason: rule.reason,
      );
    }

    if (memo.type == 'journal' && !suggestions.containsKey('生活')) {
      suggestions['生活'] = const LocalMemoClassificationSuggestion(
        tag: '生活',
        confidence: 0.52,
        reason: '日记类内容默认进入生活记录。',
      );
    }

    if (suggestions.isEmpty) {
      suggestions['生活'] = const LocalMemoClassificationSuggestion(
        tag: '生活',
        confidence: 0.42,
        reason: '未命中明确分类，先作为生活记录待后续确认。',
      );
      suggestions['待整理'] = const LocalMemoClassificationSuggestion(
        tag: '待整理',
        confidence: 0.40,
        reason: 'AI 置信度较低，需要用户稍后整理。',
      );
    }

    final items = suggestions.values.toList()
      ..sort((a, b) {
        final byConfidence = b.confidence.compareTo(a.confidence);
        return byConfidence != 0 ? byConfidence : a.tag.compareTo(b.tag);
      });
    return items.take(4).toList(growable: false);
  }

  LocalTagRule tagRuleFor(String tag) {
    for (final rule in rules) {
      if (rule.tag == tag) return rule;
    }
    return LocalTagRule(
      tag: tag,
      colorToken: 'gray',
      iconToken: 'tag',
      sortOrder: 200,
      keywords: const [],
      reason: '用户自定义标签。',
    );
  }

  bool _looksLikeList(String content) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length >= 3) {
      final markerCount = lines
          .where((line) => RegExp(r'^([-*•]|\d+[.)]|\[[ xX]\])\s*').hasMatch(line))
          .length;
      return markerCount >= 2;
    }
    return content.contains('、') && content.split('、').length >= 4;
  }
}
