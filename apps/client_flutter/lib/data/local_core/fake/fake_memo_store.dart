part of '../fake_local_core_bridge.dart';

mixin _FakeMemoStore on _FakeLocalCoreState {
  @override
  Future<LocalMemoRecord> createMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final now = context.effectiveNow;
    final memo = LocalMemoRecord(
      id: _nextStableId('memo'),
      type: input['type'] as String? ?? 'memo',
      title: input['title'] as String?,
      contentMarkdown: input['content_markdown'] as String? ?? '',
      tags: (input['tags'] as List?)?.whereType<String>().toList() ?? const [],
      status: 'active',
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    _memos.insert(0, memo);
    await generateMemoClassifications({'memo_id': memo.id}, context);
    return memo;
  }

  @override
  Future<List<LocalMemoRecord>> searchMemos(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final q = (input['q'] as String? ?? '').trim().toLowerCase();
    final limit = input['limit'] as int? ?? 20;
    return _memos
        .where((memo) => memo.status == 'active')
        .where(
          (memo) =>
              q.isEmpty ||
              '${memo.title ?? ''}\n${memo.contentMarkdown}'
                  .toLowerCase()
                  .contains(q),
        )
        .take(limit)
        .toList();
  }

  @override
  Future<LocalMemoRecord> updateMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final index = _memos.indexWhere(
      (memo) => memo.id == memoId && memo.status == 'active',
    );
    if (index < 0) throw StateError('Memo not found: $memoId');

    final old = _memos[index];
    final updated = LocalMemoRecord(
      id: old.id,
      type: input['type'] as String? ?? old.type,
      title: input.containsKey('title') ? input['title'] as String? : old.title,
      contentMarkdown:
          input['content_markdown'] as String? ?? old.contentMarkdown,
      tags: (input['tags'] as List?)?.whereType<String>().toList() ?? old.tags,
      status: old.status,
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _memos[index] = updated;
    await generateMemoClassifications({'memo_id': updated.id}, context);
    return updated;
  }

  @override
  Future<LocalMemoRecord> deleteMemo(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final index = _memos.indexWhere(
      (memo) => memo.id == memoId && memo.status == 'active',
    );
    if (index < 0) throw StateError('Memo not found: $memoId');

    final old = _memos[index];
    final deleted = LocalMemoRecord(
      id: old.id,
      type: old.type,
      title: old.title,
      contentMarkdown: old.contentMarkdown,
      tags: old.tags,
      status: input['status'] as String? ?? 'deleted',
      revision: old.revision + 1,
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _memos[index] = deleted;
    return deleted;
  }

  @override
  Future<List<LocalMemoClassification>> getMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final status = input['classification_status'] as String?;
    return _memoClassifications
        .where((item) => memoId == null || item.memoId == memoId)
        .where((item) => status == null || item.status == status)
        .toList(growable: false);
  }

  @override
  Future<List<LocalMemoClassification>> generateMemoClassifications(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final memoId = input['memo_id'] as String? ?? input['id'] as String?;
    final memo = _memos.firstWhere(
      (item) => item.id == memoId && item.status == 'active',
    );
    _memoClassifications.removeWhere(
      (item) =>
          item.memoId == memo.id &&
          item.source == 'ai' &&
          item.status == 'suggested',
    );
    final existing = _memoClassifications
        .where((item) => item.memoId == memo.id && item.status != 'rejected')
        .map((item) => item.tag)
        .toSet();
    final now = context.effectiveNow;
    for (final tag in memo.tags.where((tag) => tag.trim().isNotEmpty)) {
      _ensureFakeTagMetadata(tag.trim(), context);
      if (existing.add(tag.trim())) {
        _memoClassifications.add(
          LocalMemoClassification(
            id: _nextStableId('memo_cls'),
            memoId: memo.id,
            tag: tag.trim(),
            source: 'user',
            status: 'confirmed',
            confidence: 1,
            reason: '来自用户手动标签。',
            createdAt: now,
            updatedAt: now,
            confirmedAt: now,
          ),
        );
      }
    }
    for (final suggestion
        in const LocalMemoClassificationEngine().classify(memo)) {
      _ensureFakeTagMetadata(suggestion.tag, context);
      if (!existing.add(suggestion.tag)) continue;
      _memoClassifications.add(
        LocalMemoClassification(
          id: _nextStableId('memo_cls'),
          memoId: memo.id,
          tag: suggestion.tag,
          source: 'ai',
          status: 'suggested',
          confidence: suggestion.confidence,
          reason: suggestion.reason,
          createdAt: now,
          updatedAt: now,
          confirmedAt: null,
        ),
      );
    }
    return getMemoClassifications({'memo_id': memo.id}, context);
  }

  @override
  Future<LocalMemoClassification> confirmMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _upsertClassification(input, context, 'confirmed');
  }

  @override
  Future<LocalMemoClassification> rejectMemoClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    return _upsertClassification(input, context, 'rejected');
  }

  @override
  Future<List<LocalTagSummary>> getTagSummary(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final counts = <String, List<LocalMemoClassification>>{};
    for (final item in _memoClassifications.where(
      (item) => item.status != 'rejected',
    )) {
      counts.putIfAbsent(item.tag, () => []).add(item);
    }
    return counts.entries
        .map((entry) {
          final confirmed = entry.value
              .where((item) => item.status == 'confirmed')
              .length;
          final suggested = entry.value
              .where((item) => item.status == 'suggested')
              .length;
          return LocalTagSummary(
            tag: entry.key,
            kind: input['kind'] as String? ?? 'memo',
            count: entry.value.length,
            confirmedCount: confirmed,
            suggestedCount: suggested,
            colorToken: null,
            iconToken: null,
            sortOrder: null,
          );
        })
        .toList(growable: false)
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  @override
  Future<List<LocalTagMetadata>> listTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final kind = input['kind'] as String? ?? 'memo';
    final status = input['status'] as String? ?? 'active';
    return _tagMetadata
        .where((item) => item.kind == kind && item.status == status)
        .toList(growable: false)
      ..sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
  }

  @override
  Future<LocalTagMetadata> upsertTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final name = (input['name'] as String?)?.trim();
    if (name == null || name.isEmpty) throw ArgumentError('name is required');
    return _ensureFakeTagMetadata(
      name,
      context,
      colorToken: input['color_token'] as String?,
      iconToken: input['icon_token'] as String?,
      sortOrder: input['sort_order'] as int?,
      status: input['status'] as String? ?? 'active',
      overrideExisting: true,
    );
  }

  @override
  Future<LocalTagMetadata> deleteTagMetadata(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final name = (input['name'] as String?)?.trim();
    if (name == null || name.isEmpty) throw ArgumentError('name is required');
    final index = _tagMetadata.indexWhere((item) => item.name == name);
    if (index < 0) throw StateError('Tag metadata not found: $name');
    final old = _tagMetadata[index];
    final updated = LocalTagMetadata(
      id: old.id,
      name: old.name,
      kind: old.kind,
      colorToken: old.colorToken,
      iconToken: old.iconToken,
      sortOrder: old.sortOrder,
      status: 'deleted',
      createdAt: old.createdAt,
      updatedAt: context.effectiveNow,
    );
    _tagMetadata[index] = updated;
    return updated;
  }

  LocalMemoClassification _upsertClassification(
    Map<String, Object?> input,
    LocalCoreContext context,
    String status,
  ) {
    final classificationId =
        input['classification_id'] as String? ?? input['id'] as String?;
    final memoId = input['memo_id'] as String?;
    final tag = input['tag'] as String?;
    final index = classificationId == null
        ? -1
        : _memoClassifications.indexWhere(
            (item) => item.id == classificationId,
          );
    final old = index < 0 ? null : _memoClassifications[index];
    if (old == null && (memoId == null || tag == null || tag.trim().isEmpty)) {
      throw ArgumentError(
        'memo_id and tag are required when classification_id is not provided',
      );
    }
    final now = context.effectiveNow;
    final item = LocalMemoClassification(
      id: old?.id ?? _nextStableId('memo_cls'),
      memoId: old?.memoId ?? memoId!,
      tag: old?.tag ?? tag!.trim(),
      source: old?.source ?? input['source'] as String? ?? 'user',
      status: status,
      confidence:
          old?.confidence ?? (input['confidence'] as num?)?.toDouble(),
      reason: old?.reason ?? input['reason'] as String?,
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
      confirmedAt: status == 'confirmed' ? now : null,
    );
    if (index < 0) {
      _memoClassifications.add(item);
    } else {
      _memoClassifications[index] = item;
    }
    return item;
  }

  LocalTagMetadata _ensureFakeTagMetadata(
    String tag,
    LocalCoreContext context, {
    String? colorToken,
    String? iconToken,
    int? sortOrder,
    String status = 'active',
    bool overrideExisting = false,
  }) {
    final rule = const LocalMemoClassificationEngine().tagRuleFor(tag);
    final index = _tagMetadata.indexWhere(
      (item) => item.name == tag && item.kind == 'memo',
    );
    final old = index < 0 ? null : _tagMetadata[index];
    final resolved = LocalTagMetadata(
      id: old?.id ?? _nextStableId('tag_meta'),
      name: tag,
      kind: 'memo',
      colorToken: overrideExisting
          ? colorToken
          : old?.colorToken ?? colorToken ?? rule.colorToken,
      iconToken: overrideExisting
          ? iconToken
          : old?.iconToken ?? iconToken ?? rule.iconToken,
      sortOrder: overrideExisting
          ? sortOrder
          : old?.sortOrder ?? sortOrder ?? rule.sortOrder,
      status: status,
      createdAt: old?.createdAt ?? context.effectiveNow,
      updatedAt: context.effectiveNow,
    );
    if (index < 0) {
      _tagMetadata.add(resolved);
    } else {
      _tagMetadata[index] = resolved;
    }
    return resolved;
  }
}
