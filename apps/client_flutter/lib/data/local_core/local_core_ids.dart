typedef LocalCoreTimeSource = DateTime Function();

class LocalCoreIdGenerator {
  final LocalCoreTimeSource _timeSource;
  final Map<String, int> _counters = {};

  LocalCoreIdGenerator({LocalCoreTimeSource? timeSource})
      : _timeSource = timeSource ?? DateTime.now;

  String next(String prefix) {
    final sequence = _nextSequence(prefix);
    final timestamp = _timeSource().toUtc().microsecondsSinceEpoch;
    return 'local_${prefix}_${timestamp}_${sequence.toString().padLeft(4, '0')}';
  }

  String nextStable(String prefix) {
    final sequence = _nextSequence(prefix);
    return 'local_${prefix}_${sequence.toString().padLeft(4, '0')}';
  }

  int _nextSequence(String prefix) {
    final sequence = (_counters[prefix] ?? 0) + 1;
    _counters[prefix] = sequence;
    return sequence;
  }
}
