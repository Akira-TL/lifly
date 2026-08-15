import 'dart:convert';
import 'dart:io';

Future<Map<String, dynamic>> invokeOpaqueClientHelper(
  String helperPath,
  Map<String, Object?> request,
) async {
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
  final value = Platform.environment['LIFLY_OPAQUE_CLIENT_HELPER']?.trim();
  return value == null || value.isEmpty ? null : value;
}
