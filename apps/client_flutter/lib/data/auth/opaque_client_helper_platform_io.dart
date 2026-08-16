import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

const _nativeFfiHelperPath = 'lifly:opaque-native-ffi';

DynamicLibrary? _nativeOpaqueLibrary;
bool _nativeOpaqueLibraryResolved = false;

Future<Map<String, dynamic>> invokeOpaqueClientHelper(
  String helperPath,
  Map<String, Object?> request,
) async {
  if (helperPath == _nativeFfiHelperPath) {
    return _invokeNativeOpaqueClient(request);
  }

  final process = await Process.start(helperPath, const []);
  process.stdin.write(jsonEncode(request));
  await process.stdin.close();
  final stdoutText = await process.stdout.transform(utf8.decoder).join();
  final stderrText = await process.stderr.transform(utf8.decoder).join();
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
      helperPath,
      const [],
      stderrText.trim().isEmpty ? 'OPAQUE helper failed' : stderrText.trim(),
      exitCode,
    );
  }
  final decoded = jsonDecode(stdoutText);
  if (decoded is! Map) {
    throw const FormatException('OPAQUE helper response must be an object');
  }
  return decoded.cast<String, dynamic>();
}

String? opaqueClientHelperPathFromEnvironment() {
  final executable = Platform.environment['LIFLY_OPAQUE_CLIENT_HELPER']?.trim();
  if (executable != null && executable.isNotEmpty) return executable;
  return _loadNativeOpaqueLibrary() == null ? null : _nativeFfiHelperPath;
}

Map<String, dynamic> _invokeNativeOpaqueClient(Map<String, Object?> request) {
  final library = _loadNativeOpaqueLibrary();
  if (library == null) {
    throw StateError('Bundled OPAQUE native library is unavailable');
  }
  final invoke = library.lookupFunction<_NativeInvoke, _DartInvoke>(
    'lifly_opaque_client_invoke_json',
  );
  final release = library.lookupFunction<_NativeFree, _DartFree>(
    'lifly_opaque_string_free',
  );
  final input = jsonEncode(request).toNativeUtf8();
  Pointer<Utf8> output = nullptr;
  try {
    output = invoke(input);
    if (output == nullptr) {
      throw StateError('OPAQUE native library returned a null response');
    }
    final decoded = jsonDecode(output.toDartString());
    if (decoded is! Map) {
      throw const FormatException('OPAQUE native response must be an object');
    }
    final envelope = decoded.cast<String, dynamic>();
    if (envelope['ok'] != true) {
      final error = envelope['error']?.toString().trim();
      throw StateError(
        error == null || error.isEmpty
            ? 'OPAQUE native operation failed'
            : error,
      );
    }
    final response = envelope['response'];
    if (response is! Map) {
      throw const FormatException(
        'OPAQUE native response payload must be an object',
      );
    }
    return response.cast<String, dynamic>();
  } finally {
    if (output != nullptr) release(output);
    calloc.free(input);
  }
}

DynamicLibrary? _loadNativeOpaqueLibrary() {
  if (_nativeOpaqueLibraryResolved) return _nativeOpaqueLibrary;
  _nativeOpaqueLibraryResolved = true;

  final explicit = Platform.environment['LIFLY_OPAQUE_NATIVE_LIBRARY']?.trim();
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = <String>[
    if (explicit != null && explicit.isNotEmpty) explicit,
    if (Platform.isAndroid) 'liblifly_opaque_helper.so',
    if (Platform.isLinux) '$executableDir/lib/liblifly_opaque_helper.so',
    if (Platform.isLinux) 'liblifly_opaque_helper.so',
    if (Platform.isWindows) '$executableDir/lifly_opaque_helper.dll',
    if (Platform.isWindows) 'lifly_opaque_helper.dll',
    if (Platform.isMacOS)
      '$executableDir/../Frameworks/liblifly_opaque_helper.dylib',
    if (Platform.isMacOS) 'liblifly_opaque_helper.dylib',
  ];
  for (final candidate in candidates) {
    try {
      _nativeOpaqueLibrary = DynamicLibrary.open(candidate);
      return _nativeOpaqueLibrary;
    } on ArgumentError {
      // Try the next platform/package location.
    }
  }
  return null;
}

typedef _NativeInvoke = Pointer<Utf8> Function(Pointer<Utf8> input);
typedef _DartInvoke = Pointer<Utf8> Function(Pointer<Utf8> input);
typedef _NativeFree = Void Function(Pointer<Utf8> value);
typedef _DartFree = void Function(Pointer<Utf8> value);
