enum LocalCoreActorType { user, ai, system }

enum LocalCoreSourceChannel { flutter, localMcp, cloudMcp, import, system }

class LocalCoreContext {
  final LocalCoreActorType actorType;
  final LocalCoreSourceChannel sourceChannel;
  final String? toolName;
  final String? requestId;
  final DateTime? now;

  const LocalCoreContext({
    required this.actorType,
    required this.sourceChannel,
    this.toolName,
    this.requestId,
    this.now,
  });

  factory LocalCoreContext.flutterUser({DateTime? now}) {
    return LocalCoreContext(
      actorType: LocalCoreActorType.user,
      sourceChannel: LocalCoreSourceChannel.flutter,
      now: now,
    );
  }

  factory LocalCoreContext.localMcp(String toolName, {DateTime? now}) {
    return LocalCoreContext(
      actorType: LocalCoreActorType.ai,
      sourceChannel: LocalCoreSourceChannel.localMcp,
      toolName: toolName,
      now: now,
    );
  }

  DateTime get effectiveNow => now ?? DateTime.now().toUtc();
}
