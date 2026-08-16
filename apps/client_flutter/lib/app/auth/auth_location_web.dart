import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS()
extension type _History(JSObject _) implements JSObject {
  external void replaceState(JSAny? state, String unused, String url);
}

void syncAuthBrowserLocation({required bool signedIn}) {
  final window = globalContext.getProperty<JSObject>('window'.toJS);
  final location = window.getProperty<JSObject>('location'.toJS);
  final path = location.getProperty<JSString>('pathname'.toJS).toDart;
  if (!signedIn) {
    if (path != '/login') _replacePath(window, '/login');
    return;
  }
  if (path == '/login' || path == '/settings') {
    _replacePath(window, '/');
  }
}

void _replacePath(JSObject window, String path) {
  final historyObject = window.getProperty<JSObject>('history'.toJS);
  _History(historyObject).replaceState(null, '', path);
}
