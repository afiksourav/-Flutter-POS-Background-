import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/remote_file.dart';

class PosApi {
  PosApi()
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(minutes: 30),
          headers: const {'Accept': 'application/json'},
        ),
      );

  static const baseUrl = 'http://15.232.228.139/api/';
  static const _tokenKey = 'pos_api_token';

  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _token;

  String? get token => _token;

  Future<String?> savedToken() async {
    _token = await _storage.read(key: _tokenKey);
    return _token;
  }

  Future<String> login({required String username, required String password}) async {
    try {
      final response = await _dio.post<dynamic>(
        'token',
        data: {'username': username, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final Map<String, dynamic> body;
      try {
        body = _asMap(response.data);
      } on FormatException {
        throw const PosApiException('The sign-in server returned an invalid response.');
      } on TypeError {
        throw const PosApiException('The sign-in server returned an invalid response.');
      }
      final token = body['access'] ?? body['token'] ?? body['access_token'] ?? body['jwt'];
      if (token is! String || token.isEmpty) {
        throw const PosApiException('The server response did not include an authentication token.');
      }
      _token = token;
      await _storage.write(key: _tokenKey, value: token);
      return token;
    } on DioException catch (error) {
      throw PosApiException(_messageFor(error));
    }
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }

  Map<String, String> get authorizationHeaders {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const PosApiException('Please sign in again to continue.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<RemoteFile>> listFiles() async {
    final response = await _dio.get<dynamic>('get', options: _authorizedOptions());
    final files = _extractList(response.data);
    return files.map(_remoteFile).whereType<RemoteFile>().toList();
  }

  String? uploadedFileName(String? responseBody) {
    if (responseBody == null || responseBody.trim().isEmpty) return null;
    try {
      final decoded = _asMap(responseBody);
      final value = decoded['file'] ?? decoded['filename'] ?? decoded['name'] ?? decoded['url'];
      if (value is String && value.isNotEmpty) {
        return _fileNameFrom(value);
      }
    } on FormatException {
      final value = responseBody.trim();
      if (!value.startsWith('<')) return _fileNameFrom(value);
    }
    return null;
  }

  String downloadUrl(RemoteFile file) {
    if (file.url != null) {
      final parsed = Uri.tryParse(file.url!);
      if (parsed != null && parsed.hasScheme) return parsed.toString();
    }
    return Uri.parse(baseUrl).resolve('get').toString();
  }

  Map<String, String> downloadQuery(RemoteFile file) => {'file': file.name};

  Options _authorizedOptions() {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const PosApiException('Please sign in again to continue.');
    }
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final decoded = Map<String, dynamic>.from(jsonDecode(value) as Map);
      return decoded;
    }
    return {};
  }

  static List<dynamic> _extractList(dynamic body) {
    if (body is List) return body;
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      for (final key in ['files', 'results', 'data']) {
        final value = map[key];
        if (value is List) return value;
      }
    }
    throw const PosApiException('The server returned an unexpected file list. Please try again later.');
  }

  static RemoteFile? _remoteFile(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return RemoteFile(name: _fileNameFrom(value), url: value);
    }
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final candidate = map['name'] ?? map['filename'] ?? map['file'] ?? map['url'];
    if (candidate is! String || candidate.isEmpty) return null;
    final url = map['url'] is String ? map['url'] as String : null;
    return RemoteFile(name: _fileNameFrom(candidate), url: url);
  }

  static String _fileNameFrom(String value) {
    final uri = Uri.tryParse(value);
    final pathSegment =
        uri?.queryParameters['file'] ?? (uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : value);
    final filename = pathSegment.split(RegExp(r'[/\\]')).last;
    if (filename.isEmpty || filename == '.' || filename == '..') {
      throw const PosApiException('The server returned an invalid file name.');
    }
    return filename;
  }

  static String _messageFor(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'Your sign-in has expired. Please sign in again.';
    }
    if (status != null) {
      return 'The server returned an error ($status). Please try again.';
    }
    return 'Could not connect. Check your network and try again.';
  }
}

class PosApiException implements Exception {
  const PosApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
