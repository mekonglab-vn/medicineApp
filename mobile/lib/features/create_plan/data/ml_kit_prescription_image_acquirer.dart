import 'package:flutter/services.dart';

import '../domain/prescription_image_acquirer.dart';

abstract interface class PrescriptionDocumentScannerChannel {
  Future<Object?> scan({required bool allowGalleryImport});

  Future<bool> release({required String cachePath});
}

final class MethodChannelPrescriptionDocumentScanner
    implements PrescriptionDocumentScannerChannel {
  static const channelName =
      'com.medicineapp.medicine_app/prescription_document_scanner';
  static const methodName = 'scanPrescriptionDocument';
  static const releaseMethodName = 'releasePrescriptionDocument';

  final MethodChannel _channel;

  const MethodChannelPrescriptionDocumentScanner({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  @override
  Future<Object?> scan({required bool allowGalleryImport}) {
    return _channel.invokeMethod<Object?>(methodName, {
      'allow_gallery_import': allowGalleryImport,
    });
  }

  @override
  Future<bool> release({required String cachePath}) async {
    return await _channel.invokeMethod<bool>(releaseMethodName, {
          'cache_path': cachePath,
        }) ??
        false;
  }
}

final class MlKitPrescriptionImageAcquirer
    implements PrescriptionImageAcquirer {
  static const maxFileBytes = 10 * 1024 * 1024;

  final PrescriptionDocumentScannerChannel _channel;
  bool _requestInProgress = false;

  MlKitPrescriptionImageAcquirer({PrescriptionDocumentScannerChannel? channel})
    : _channel = channel ?? const MethodChannelPrescriptionDocumentScanner();

  @override
  Future<PrescriptionImageAcquisitionOutcome> acquire(
    PrescriptionImageAcquisitionOptions options,
  ) async {
    if (_requestInProgress) {
      return const PrescriptionImageAcquisitionFailure(
        code: PrescriptionImageAcquisitionFailureCode.acquisitionInProgress,
        message: 'A prescription image acquisition is already in progress.',
      );
    }

    _requestInProgress = true;
    try {
      final response = await _channel.scan(
        allowGalleryImport: options.allowGalleryFallback,
      );
      return await _mapResponse(response, options);
    } on MissingPluginException {
      return PrescriptionImageAcquisitionUnsupported(
        code: PrescriptionImageAcquisitionFailureCode.unsupportedDevice,
        eligibleFallbackSources: _eligibleFallbackSources(options),
        message: 'The document scanner is unavailable on this platform.',
      );
    } on PlatformException catch (error) {
      return _mapPlatformException(error, options);
    } catch (_) {
      return const PrescriptionImageAcquisitionFailure(
        code: PrescriptionImageAcquisitionFailureCode.unknown,
        message: 'Prescription image acquisition failed.',
      );
    } finally {
      _requestInProgress = false;
    }
  }

  @override
  Future<bool> release(AcquiredPrescriptionImage image) async {
    final cachePath = image.cachePath;
    if (image.source !=
            PrescriptionImageAcquisitionSource.mlKitDocumentScanner ||
        cachePath == null ||
        cachePath.isEmpty) {
      return false;
    }

    try {
      return await _channel.release(cachePath: cachePath);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<PrescriptionImageAcquisitionOutcome> _mapResponse(
    Object? value,
    PrescriptionImageAcquisitionOptions options,
  ) async {
    if (value is! Map) {
      return _invalidResult();
    }

    final response = Map<Object?, Object?>.from(value);
    final status = response['status'];
    if (status == 'cancelled') {
      return const PrescriptionImageAcquisitionCancelled();
    }
    if (status == 'unsupported') {
      return PrescriptionImageAcquisitionUnsupported(
        code: _failureCode(response['code']),
        eligibleFallbackSources: _eligibleFallbackSources(options),
        message: _optionalString(response['message']),
      );
    }
    if (status == 'failure') {
      return PrescriptionImageAcquisitionFailure(
        code: _failureCode(response['code']),
        message: _optionalString(response['message']),
      );
    }
    if (status != 'success') {
      return _invalidResult();
    }

    final cachePath = response['cache_path'];
    final filename = response['filename'];
    final mimeType = response['mime_type'];
    final width = response['width'];
    final height = response['height'];
    final byteSize = response['byte_size'];
    final scannerMode = response['scanner_mode'];
    final scannerVersion = response['scanner_version'];
    final elapsedMilliseconds = response['elapsed_milliseconds'];

    if (byteSize is int && byteSize > maxFileBytes) {
      await _releaseMalformedSuccessCachePath(cachePath);
      return const PrescriptionImageAcquisitionFailure(
        code: PrescriptionImageAcquisitionFailureCode.fileTooLarge,
        message: 'The scanned prescription exceeds the 10 MB limit.',
      );
    }
    if (cachePath is! String ||
        cachePath.isEmpty ||
        filename is! String ||
        filename != 'prescription.jpg' ||
        mimeType is! String ||
        mimeType != 'image/jpeg' ||
        width is! int ||
        width <= 0 ||
        height is! int ||
        height <= 0 ||
        byteSize is! int ||
        byteSize <= 0 ||
        scannerMode is! String ||
        scannerMode != 'full' ||
        scannerVersion is! String ||
        scannerVersion != '16.0.0' ||
        elapsedMilliseconds is! int ||
        elapsedMilliseconds < 0) {
      await _releaseMalformedSuccessCachePath(cachePath);
      return _invalidResult();
    }

    return PrescriptionImageAcquisitionSuccess(
      AcquiredPrescriptionImage(
        cachePath: cachePath,
        filename: filename,
        mimeType: mimeType,
        width: width,
        height: height,
        byteSize: byteSize,
        source: PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
        scannerMetadata: PrescriptionScannerMetadata(
          mode: scannerMode,
          version: scannerVersion,
          elapsedMilliseconds: elapsedMilliseconds,
        ),
      ),
    );
  }

  Future<void> _releaseMalformedSuccessCachePath(Object? value) async {
    if (value is! String || value.isEmpty) return;
    try {
      await _channel.release(cachePath: value);
    } catch (_) {
      // The malformed acquisition still fails even if best-effort cleanup fails.
    }
  }

  PrescriptionImageAcquisitionOutcome _mapPlatformException(
    PlatformException error,
    PrescriptionImageAcquisitionOptions options,
  ) {
    final code = _failureCode(error.code);
    if (code == PrescriptionImageAcquisitionFailureCode.unsupportedDevice ||
        code ==
            PrescriptionImageAcquisitionFailureCode
                .googlePlayServicesUnavailable) {
      return PrescriptionImageAcquisitionUnsupported(
        code: code,
        eligibleFallbackSources: _eligibleFallbackSources(options),
        message: 'The document scanner is unavailable.',
      );
    }
    return PrescriptionImageAcquisitionFailure(
      code: code,
      message: 'Prescription image acquisition failed.',
    );
  }

  Set<PrescriptionImageAcquisitionSource> _eligibleFallbackSources(
    PrescriptionImageAcquisitionOptions options,
  ) {
    return {
      if (options.allowCameraXFallback)
        PrescriptionImageAcquisitionSource.cameraXFallback,
      if (options.allowGalleryFallback)
        PrescriptionImageAcquisitionSource.galleryFallback,
    };
  }

  PrescriptionImageAcquisitionFailureCode _failureCode(Object? value) {
    return PrescriptionImageAcquisitionFailureCode.values.firstWhere(
      (code) => code.value == value,
      orElse: () => PrescriptionImageAcquisitionFailureCode.unknown,
    );
  }

  String? _optionalString(Object? value) => value is String ? value : null;

  PrescriptionImageAcquisitionFailure _invalidResult() {
    return const PrescriptionImageAcquisitionFailure(
      code: PrescriptionImageAcquisitionFailureCode.invalidResult,
      message: 'The document scanner returned an invalid result.',
    );
  }
}
