import 'dart:convert';

import 'package:client_flutter/data/auth/pake_client_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'OPAQUE helper adapter transports registration and export key contract',
    () async {
      final calls = <Map<String, Object?>>[];
      final adapter = JsonHelperOpaqueClientAdapter(
        helperPath: '/tmp/opaque-client-helper',
        invokeHelper: (path, request) async {
          expect(path, '/tmp/opaque-client-helper');
          calls.add(Map<String, Object?>.from(request));
          switch (request['operation']) {
            case 'client_registration_start':
              return {
                'client_request': 'registration-request',
                'client_state': 'registration-state',
              };
            case 'client_registration_finish':
              return {
                'client_message': 'registration-upload',
                'export_key': base64Url
                    .encode([1, 2, 3, 4])
                    .replaceAll('=', ''),
              };
          }
          throw StateError('unexpected operation');
        },
      );

      final start = await adapter.startRegistration(
        password: 'local-only-password',
      );
      expect(start.clientRequest, 'registration-request');
      expect(start.clientState, 'registration-state');

      final finish = await adapter.finishRegistration(
        clientState: start.clientState,
        serverResponse: 'server-registration-response',
      );
      expect(finish.clientMessage, 'registration-upload');
      expect(finish.exportKey, [1, 2, 3, 4]);

      expect(calls, hasLength(2));
      expect(calls.first['protocol'], 'opaque-rfc9807');
      expect(calls.first['protocol_version'], 1);
      expect(calls.first['operation'], 'client_registration_start');
      expect(calls.first['password'], 'local-only-password');
      expect(calls.last['operation'], 'client_registration_finish');
      expect(calls.last['client_state'], 'registration-state');
      expect(calls.last['server_response'], 'server-registration-response');
    },
  );

  test(
    'OPAQUE helper adapter supports login and sanitizes helper failures',
    () async {
      final adapter = JsonHelperOpaqueClientAdapter(
        helperPath: '/tmp/opaque-client-helper',
        invokeHelper: (helperPath, request) async {
          expect(helperPath, '/tmp/opaque-client-helper');
          switch (request['operation']) {
            case 'client_login_start':
              return {
                'client_request': 'login-request',
                'client_state': 'login-state',
              };
            case 'client_login_finish':
              expect(request['password'], 'password');
              return {
                'client_message': 'login-finish',
                'export_key': base64Url.encode([9, 8, 7]),
              };
          }
          throw StateError('unexpected operation');
        },
      );

      final start = await adapter.startLogin(password: 'password');
      final finish = await adapter.finishLogin(
        clientState: start.clientState,
        serverResponse: 'server-login-response',
      );
      expect(start.clientRequest, 'login-request');
      expect(finish.clientMessage, 'login-finish');
      expect(finish.exportKey, [9, 8, 7]);

      final failing = JsonHelperOpaqueClientAdapter(
        helperPath: '/tmp/opaque-client-helper',
        invokeHelper: (helperPath, request) async {
          expect(helperPath, '/tmp/opaque-client-helper');
          expect(request, isNotEmpty);
          throw StateError('secret helper detail must not escape');
        },
      );
      await expectLater(
        failing.startLogin(password: 'password'),
        throwsA(
          isA<PakeClientUnavailable>().having(
            (error) => error.message,
            'message',
            'OPAQUE client helper execution failed',
          ),
        ),
      );
    },
  );

  test(
    'OPAQUE helper adapter consumes the local password after finish',
    () async {
      var finishCalls = 0;
      final adapter = JsonHelperOpaqueClientAdapter(
        helperPath: '/tmp/opaque-client-helper',
        invokeHelper: (helperPath, request) async {
          switch (request['operation']) {
            case 'client_login_start':
              return {'client_request': 'request', 'client_state': 'state'};
            case 'client_login_finish':
              finishCalls += 1;
              return {
                'client_message': 'finish',
                'export_key': base64Url.encode([1, 2, 3]),
              };
          }
          throw StateError('unexpected operation');
        },
      );

      final start = await adapter.startLogin(password: 'secret');
      await adapter.finishLogin(
        clientState: start.clientState,
        serverResponse: 'response',
      );
      await expectLater(
        adapter.finishLogin(
          clientState: start.clientState,
          serverResponse: 'response',
        ),
        throwsA(isA<PakeClientUnavailable>()),
      );
      expect(finishCalls, 1);
    },
  );
}
