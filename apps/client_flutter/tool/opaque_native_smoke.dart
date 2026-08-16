import 'dart:io';

import 'package:client_flutter/data/auth/pake_client_adapter.dart';

Future<void> main() async {
  final adapter = defaultPakeClientAdapter();
  if (adapter is UnavailableOpaqueClientAdapter) {
    throw StateError('Bundled native OPAQUE adapter is unavailable');
  }
  final started = await adapter.startRegistration(
    password: 'lifly-native-opaque-smoke-password',
  );
  if (started.clientRequest.isEmpty || started.clientState.isEmpty) {
    throw StateError(
      'Native OPAQUE registration start returned an empty payload',
    );
  }
  stdout.writeln(
    'OPAQUE_NATIVE_SMOKE=PASS protocol=${adapter.protocol} '
    'version=${adapter.protocolVersion}',
  );
}
