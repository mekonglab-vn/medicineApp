import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/network/dio_client.dart';
import '../domain/scan_result.dart';

/// Scan repository — upload prescription image → OCR.
class ScanRepository {
  final Dio _dio;

  ScanRepository(this._dio);

  /// Upload image bytes → AI OCR pipeline → drug list.
  Future<ScanResult> uploadPrescription({
    required Uint8List imageBytes,
    required String filename,
    String mimeType = 'image/jpeg',
    String? ocrText,
    List<Map<String, dynamic>>? ocrLines,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        imageBytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
      if (ocrText != null && ocrText.isNotEmpty) 'ocr_text': ocrText,
      if (ocrLines != null && ocrLines.isNotEmpty) 'ocr_lines': jsonEncode(ocrLines),
    });

    final response = await _dio.post(
      '/scan',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    return ScanResult.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<String> startSession() async {
    final response = await _dio.post('/scan/session/start');
    final data = response.data['data'] as Map<String, dynamic>;
    return data['sessionId'] as String;
  }

  Future<ScanResult> addImageToSession({
    required String sessionId,
    required Uint8List imageBytes,
    required String filename,
    String mimeType = 'image/jpeg',
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        imageBytes,
        filename: filename,
        contentType: MediaType.parse(mimeType),
      ),
    });

    final response = await _dio.post(
      '/scan/session/$sessionId/add-image',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    return ScanResult.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<ScanResult> stopSession(String sessionId) async {
    final response = await _dio.post('/scan/session/$sessionId/stop');
    return ScanResult.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}

final scanRepositoryProvider = Provider<ScanRepository>((ref) {
  return ScanRepository(ref.watch(dioProvider));
});
