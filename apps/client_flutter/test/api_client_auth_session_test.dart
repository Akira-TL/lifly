import 'package:client_flutter/data/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared ApiClient reads the current secure-session token on every request',
    () async {
      String? token;
      final dio = Dio(BaseOptions(baseUrl: 'http://example.invalid/api/v1'));
      final api = ApiClient(
        baseUrl: 'http://example.invalid/api/v1',
        dio: dio,
        accessTokenProvider: () async => token,
      );
      final seen = <String?>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            seen.add(options.headers['Authorization'] as String?);
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'ok': true},
              ),
            );
          },
        ),
      );

      await api.get('/probe');
      token = 'access-v1';
      await api.get('/probe');
      token = 'access-v2';
      await api.get('/probe');
      token = null;
      await api.get('/probe');

      expect(seen, [null, 'Bearer access-v1', 'Bearer access-v2', null]);
    },
  );
}
