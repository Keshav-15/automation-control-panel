import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../base/utils/constants/preference_key_constant.dart';
import '../base/utils/preference_utils.dart';
import 'error_utils.dart';

class ApiService {
  static final _createDio = createDio();
  static final _dio = addInterceptors(_createDio);

  static BaseOptions options = BaseOptions(
    baseUrl: dotenv.env['BASE_URL'] ?? "",
    responseType: ResponseType.json,
    contentType: 'application/json',
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  );

  static Dio createDio() {
    return Dio(options);
  }

  static Dio addInterceptors(Dio dio) {
    return dio
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers.addAll({'X-Auth-Token': getString(prefkeyToken)});
            if (kDebugMode) {
              log(options.headers.toString(), name: "Headers");
              log(options.baseUrl.toString() + options.path, name: "BaseURL");
              log(options.queryParameters.toString(), name: "QueryParam");
              log(options.data.toString(), name: "Data");
            }
            return handler.next(options);
          },
          onResponse: (e, handler) {
            if (kDebugMode) {
              log(e.statusCode.toString(), name: "Code");
              log(e.toString(), name: "Response");
            }
            return handler.next(e);
          },
          onError: (e, handler) {
            if (kDebugMode) {
              log(e.error.toString(), name: "Error");
              log(e.response.toString(), name: "Error Data");
            }
            handleHttpError(e);
            //return handler.next(e);
          },
        ),
      );
  }

  Future<Response?> get(
    String endUrl, {
    Map<String, dynamic>? params,
    Options? options,
  }) async {
    if (await checkInternet()) {
      return await (_dio.get(
        endUrl,
        queryParameters: params,
        options: options,
      ));
    }
    return null;
  }

  Future<Response?> post(
    String endUrl, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? params,
    Options? options,
  }) async {
    if (await checkInternet()) {
      return await (_dio.post(
        endUrl,
        data: data,
        queryParameters: params,
        options: options,
      ));
    }
    return null;
  }

  Future<Response?> delete(
    String endUrl, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? params,
    Options? options,
    bool isCompanyCheck = false,
  }) async {
    if (await checkInternet()) {
      return await (_dio.delete(
        endUrl,
        data: data,
        queryParameters: params,
        options: options,
      ));
    }
    return null;
  }

  Future<Response?> multipartPost(
    String endUrl, {
    required FormData data,
    Options? options,
  }) async {
    if (await checkInternet()) {
      return await (_dio.post(endUrl, data: data, options: options));
    }
    return null;
  }
}
