import 'package:dio/dio.dart';

class ApiBinaryResponse {
  final List<int> bytes;
  final Map<String, String> headers;

  const ApiBinaryResponse({required this.bytes, required this.headers});

  String? header(String name) => headers[name.toLowerCase()];
}

class ApiClient {
  late final Dio _dio;
  final String baseUrl;

  ApiClient({this.baseUrl = 'http://127.0.0.1:8310/api/v1', Dio? dio}) {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 10),
            headers: {'Content-Type': 'application/json'},
          ),
        );
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _dio.get(path, queryParameters: params);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final response = await _dio.post(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postMultipartBytes(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, dynamic>? fields,
    Map<String, dynamic>? params,
  }) async {
    final formData = FormData.fromMap({
      ...?fields,
      fieldName: MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _dio.post(
      path,
      data: formData,
      queryParameters: params,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.data as Map<String, dynamic>;
  }

  Future<ApiBinaryResponse> downloadBytes(
    String path, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _dio.get<List<int>>(
      path,
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return ApiBinaryResponse(
      bytes: response.data ?? const [],
      headers: _flattenHeaders(response.headers),
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final response = await _dio.put(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _dio.delete(path);
    return response.data as Map<String, dynamic>;
  }

  Map<String, String> _flattenHeaders(Headers headers) {
    return headers.map.map(
      (key, values) => MapEntry(key.toLowerCase(), values.join(',')),
    );
  }
}
