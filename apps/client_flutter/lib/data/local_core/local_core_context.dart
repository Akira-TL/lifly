enum LocalCoreActorType { user, ai, system }

enum LocalCoreSourceChannel { flutter, localMcp, cloudMcp, import, system }

const defaultLocalCoreUserId = 'local-dev';

class LocalCoreContext {
  final LocalCoreActorType actorType;
  final LocalCoreSourceChannel sourceChannel;
  final String userId;
  final String? actorId;
  final String? toolName;
  final String? requestId;
  final String? sourceText;
  final DateTime? now;

  const LocalCoreContext({
    required this.actorType,
    required this.sourceChannel,
    this.userId = defaultLocalCoreUserId,
    this.actorId,
    this.toolName,
    this.requestId,
    this.sourceText,
    this.now,
  });

  factory LocalCoreContext.flutterUser({
    String userId = defaultLocalCoreUserId,
    DateTime? now,
  }) {
    return LocalCoreContext(
      actorType: LocalCoreActorType.user,
      sourceChannel: LocalCoreSourceChannel.flutter,
      userId: userId,
      now: now,
    );
  }

  factory LocalCoreContext.localMcp(
    String toolName, {
    String userId = defaultLocalCoreUserId,
    DateTime? now,
  }) {
    return LocalCoreContext(
      actorType: LocalCoreActorType.ai,
      sourceChannel: LocalCoreSourceChannel.localMcp,
      userId: userId,
      toolName: toolName,
      now: now,
    );
  }

  DateTime get effectiveNow => (now ?? DateTime.now()).toUtc();

  String get actorTypeName => actorType.name;

  String get sourceChannelName => sourceChannel.name;

  String timestamp() => effectiveNow.toIso8601String();
}
