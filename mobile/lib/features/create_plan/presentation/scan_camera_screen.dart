import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/network/network_error_mapper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../data/scan_repository.dart';

enum _ScanStage {
  idle,
  scanning,
  ocrProcessing,
  uploading,
  error,
}

class ScanCameraScreen extends ConsumerStatefulWidget {
  const ScanCameraScreen({super.key});

  @override
  ConsumerState<ScanCameraScreen> createState() => _ScanCameraScreenState();
}

class _ScanCameraScreenState extends ConsumerState<ScanCameraScreen> {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  _ScanStage _stage = _ScanStage.idle;
  List<String> _scannedImages = [];
  String? _extractedText;
  List<Map<String, dynamic>>? _extractedLines;
  String? _statusText;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _startMlKitScan();
      }
    });
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _startMlKitScan() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _stage = _ScanStage.scanning;
      _statusText = 'Đang mở máy ảnh quét đơn thuốc...';
      _errorText = null;
    });

    try {
      // 1. Mở camera plugin ML Kit Document Scanner (cho phép chụp, cắt góc, xoay, chỉnh sửa tùy ý)
      final options = DocumentScannerOptions(
        pageLimit: 10,
        isGalleryImport: true,
        mode: ScannerMode.full,
      );

      final documentScanner = DocumentScanner(options: options);
      final result = await documentScanner.scanDocument();
      documentScanner.close();

      final images = result.images;
      if (images == null || images.isEmpty) {
        if (!mounted) return;
        setState(() {
          _stage = _ScanStage.idle;
          _statusText = 'Chưa chọn hoặc chụp ảnh đơn thuốc nào.';
        });
        return;
      }

      // 2. Người dùng đã xác nhận lưu ảnh -> Chạy OCR ngầm bằng ML Kit Text Recognition
      setState(() {
        _scannedImages = images;
        _stage = _ScanStage.ocrProcessing;
        _statusText = 'Đang trích xuất chữ viết (OCR ngầm)...';
      });

      StringBuffer ocrBuffer = StringBuffer();
      List<Map<String, dynamic>> extractedLines = [];

      for (int i = 0; i < images.length; i++) {
        final imagePath = images[i];
        final inputImage = InputImage.fromFilePath(imagePath);
        final RecognizedText recognizedText =
            await _textRecognizer.processImage(inputImage);

        if (recognizedText.text.isNotEmpty) {
          ocrBuffer.writeln("--- TRANG ${i + 1} ---");
          ocrBuffer.writeln(recognizedText.text);
          ocrBuffer.writeln();

          for (int bIdx = 0; bIdx < recognizedText.blocks.length; bIdx++) {
            final block = recognizedText.blocks[bIdx];
            for (int lIdx = 0; lIdx < block.lines.length; lIdx++) {
              final line = block.lines[lIdx];
              final rect = line.boundingBox;
              extractedLines.add({
                'text': line.text,
                'bbox': {
                  'left': rect.left,
                  'top': rect.top,
                  'right': rect.right,
                  'bottom': rect.bottom,
                },
                'confidence': line.confidence ?? 0.95,
                'block_index': bIdx,
                'line_index': lIdx,
                'page': i + 1,
              });
            }
          }
        }
      }

      _extractedText = ocrBuffer.toString().trim();
      _extractedLines = extractedLines;

      // 3. Tự động đọc dữ liệu ảnh đã nắn góc và gửi thông tin về máy chủ xử lý như cũ
      final firstImageFile = File(images.first);
      final bytes = await firstImageFile.readAsBytes();
      final filename =
          'scan_mlkit_${DateTime.now().millisecondsSinceEpoch}.jpg';

      setState(() {
        _stage = _ScanStage.uploading;
        _statusText = 'Đang gửi thông tin về máy chủ phân loại đơn thuốc...';
      });

      await _uploadCapturedImage(bytes, filename);
    } catch (e) {
      if (!mounted) return;
      final issue = classifyNetworkIssue(e);
      var message = l10n.scanCameraErrorGeneric;
      switch (issue) {
        case NetworkIssueKind.noConnection:
          message = l10n.scanCameraErrorConnection;
          break;
        case NetworkIssueKind.timeout:
          message = l10n.scanCameraErrorTimeout;
          break;
        case NetworkIssueKind.serviceUnavailable:
        case NetworkIssueKind.serverError:
          message = l10n.scanCameraErrorUnavailable;
          break;
        case NetworkIssueKind.unauthorized:
        case NetworkIssueKind.unknown:
          message = e.toString();
          break;
      }

      setState(() {
        _stage = _ScanStage.error;
        _statusText = message;
        _errorText = message;
      });
    }
  }

  Future<void> _uploadCapturedImage(Uint8List bytes, String filename) async {
    final l10n = AppLocalizations.of(context);

    try {
      final repo = ref.read(scanRepositoryProvider);
      final result = await repo.uploadPrescription(
        imageBytes: bytes,
        filename: filename,
        ocrText: _extractedText,
        ocrLines: _extractedLines,
      );

      if (!mounted) return;

      if (result.drugs.isEmpty) {
        setState(() {
          _stage = _ScanStage.error;
          _statusText = l10n.scanCameraNodrugFound;
          _errorText = l10n.scanCameraNodrugFound;
        });
        return;
      }

      // Đã nhận phản hồi thành công từ server -> Điều hướng tới màn hình xem kết quả như cũ
      context.go('/create/review', extra: result);
    } catch (e) {
      if (!mounted) return;
      final issue = classifyNetworkIssue(e);
      var message = l10n.scanCameraErrorGeneric;
      switch (issue) {
        case NetworkIssueKind.noConnection:
          message = l10n.scanCameraErrorConnection;
          break;
        case NetworkIssueKind.timeout:
          message = l10n.scanCameraErrorTimeout;
          break;
        case NetworkIssueKind.serviceUnavailable:
        case NetworkIssueKind.serverError:
          message = l10n.scanCameraErrorUnavailable;
          break;
        case NetworkIssueKind.unauthorized:
        case NetworkIssueKind.unknown:
          message = e.toString();
          break;
      }

      setState(() {
        _stage = _ScanStage.error;
        _statusText = message;
        _errorText = message;
      });
    }
  }

  void _showGuide() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.scanCameraGuideTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text('1. ${l10n.scanCameraGuideStep1}'),
              const SizedBox(height: 8),
              Text('2. ${l10n.scanCameraGuideStep2}'),
              const SizedBox(height: 8),
              Text('3. ${l10n.scanCameraGuideStep3}'),
              const SizedBox(height: 8),
              Text('4. ${l10n.scanCameraGuideStep4}'),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.scanCameraTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/create');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showGuide,
            tooltip: l10n.scanCameraGuide,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusCard(),
              const SizedBox(height: 20),
              Expanded(
                child: _buildMainContent(),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: (_stage == _ScanStage.scanning ||
                        _stage == _ScanStage.ocrProcessing ||
                        _stage == _ScanStage.uploading)
                    ? null
                    : _startMlKitScan,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  _stage == _ScanStage.idle
                      ? 'Bắt đầu quét đơn thuốc'
                      : 'Quét lại đơn thuốc',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    Color cardColor = AppColors.primary;
    IconData icon = Icons.info_outline;

    switch (_stage) {
      case _ScanStage.idle:
        cardColor = AppColors.primary;
        icon = Icons.touch_app;
        break;
      case _ScanStage.scanning:
        cardColor = AppColors.warning;
        icon = Icons.camera_enhance;
        break;
      case _ScanStage.ocrProcessing:
        cardColor = AppColors.primaryDark;
        icon = Icons.psychology;
        break;
      case _ScanStage.uploading:
        cardColor = AppColors.info;
        icon = Icons.cloud_upload;
        break;
      case _ScanStage.error:
        cardColor = AppColors.error;
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cardColor, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _statusText ?? 'Sẵn sàng quét đơn thuốc',
              style: TextStyle(
                color: cardColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          if (_stage == _ScanStage.scanning ||
              _stage == _ScanStage.ocrProcessing ||
              _stage == _ScanStage.uploading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_stage == _ScanStage.error) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                _errorText ?? 'Có lỗi xảy ra',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    if (_scannedImages.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ảnh đơn thuốc đã quét:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _scannedImages.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  width: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: FileImage(File(_scannedImages[index])),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (_extractedText != null && _extractedText!.isNotEmpty) ...[
            const Text(
              'Chữ viết trích xuất ngầm (ML Kit OCR):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _extractedText!,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 72,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tự động quét & phân tích đơn thuốc',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Nhấn nút bên dưới để mở máy ảnh quét tài liệu. Hệ thống hỗ trợ chụp, cắt lề, xoay và tự động nhận diện thông tin thuốc.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
