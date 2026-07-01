enum LiflyDataMode {
  api,
  local;

  static LiflyDataMode fromName(String value) {
    return switch (value.trim().toLowerCase()) {
      'local' => LiflyDataMode.local,
      _ => LiflyDataMode.api,
    };
  }

  String get label {
    return switch (this) {
      LiflyDataMode.api => 'Cloud API',
      LiflyDataMode.local => 'Local Core',
    };
  }
}
