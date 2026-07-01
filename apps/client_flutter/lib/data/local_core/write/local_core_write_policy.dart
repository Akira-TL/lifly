import 'package:client_flutter/data/local_core/local_core_context.dart';
import 'package:client_flutter/data/local_core/local_core_ids.dart';

class LocalCoreWritePolicy {
  final LocalCoreIdGenerator idGenerator;

  LocalCoreWritePolicy({LocalCoreIdGenerator? idGenerator})
    : idGenerator = idGenerator ?? LocalCoreIdGenerator();

  String nextEntityId(String prefix) => idGenerator.next(prefix);

  String nextAuditLogId() => idGenerator.next('audit');

  int initialRevision() => 1;

  int nextRevision(int currentRevision) => currentRevision + 1;

  LocalCoreWriteTimestamps timestampsFor(LocalCoreContext context) {
    return LocalCoreWriteTimestamps.same(context.effectiveNow);
  }

  LocalCoreWriteMetadata metadataForCreate(LocalCoreContext context) {
    return LocalCoreWriteMetadata(
      userId: context.userId,
      source: context.sourceChannelName,
      revision: initialRevision(),
      timestamps: timestampsFor(context),
    );
  }

  LocalCoreWriteMetadata metadataForUpdate(
    LocalCoreContext context, {
    required int currentRevision,
    required DateTime createdAt,
  }) {
    return LocalCoreWriteMetadata(
      userId: context.userId,
      source: context.sourceChannelName,
      revision: nextRevision(currentRevision),
      timestamps: LocalCoreWriteTimestamps(
        createdAt: createdAt.toUtc(),
        updatedAt: context.effectiveNow,
      ),
    );
  }
}

class LocalCoreWriteMetadata {
  final String userId;
  final String source;
  final int revision;
  final LocalCoreWriteTimestamps timestamps;

  const LocalCoreWriteMetadata({
    required this.userId,
    required this.source,
    required this.revision,
    required this.timestamps,
  });
}

class LocalCoreWriteTimestamps {
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalCoreWriteTimestamps({
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalCoreWriteTimestamps.same(DateTime value) {
    final utc = value.toUtc();
    return LocalCoreWriteTimestamps(createdAt: utc, updatedAt: utc);
  }

  String get createdAtIso => createdAt.toIso8601String();

  String get updatedAtIso => updatedAt.toIso8601String();
}
