Future<Map<String, dynamic>> invokeOpaqueClientHelper(
  String helperPath,
  Map<String, Object?> request,
) async {
  throw UnsupportedError(
    'OPAQUE client helper process is unavailable on this platform',
  );
}

String? opaqueClientHelperPathFromEnvironment() => null;
