import 'dart:js_interop';

@JS('globalThis.liflyStartup.mark')
external void _markStartupEvent(JSString name, [JSAny? detail]);

@JS('globalThis.liflyStartup.markCoreUsable')
external void _markCoreUsable();

@JS('globalThis.liflyStartup.markThemeActivated')
external void _markThemeActivated(JSString themeId);

void markStartupEvent(String name, {String? detail}) {
  _markStartupEvent(name.toJS, detail?.toJS);
}

void markCoreUsable() {
  _markCoreUsable();
}

void markThemeActivated(String themeId) {
  _markThemeActivated(themeId.toJS);
}
