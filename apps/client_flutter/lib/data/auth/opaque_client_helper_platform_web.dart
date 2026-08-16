import 'dart:convert';
import 'dart:js_interop';

@JS('liflyOpaqueClientInvoke')
external JSPromise<JSString> _liflyOpaqueClientInvoke(JSString requestJson);

Future<Map<String, dynamic>> invokeOpaqueClientHelper(
  String helperPath,
  Map<String, Object?> request,
) async {
  try {
    final responseText = (await _liflyOpaqueClientInvoke(jsonEncode(request).toJS).toDart)
        .toDart;
    final decoded = jsonDecode(responseText);
    if (decoded is! Map) {
      throw const FormatException('OPAQUE WebAssembly response must be an object');
    }
    return decoded.cast<String, dynamic>();
  } catch (_) {
    throw StateError('OPAQUE WebAssembly client invocation failed');
  }
}

String? opaqueClientHelperPathFromEnvironment() => 'webassembly';
