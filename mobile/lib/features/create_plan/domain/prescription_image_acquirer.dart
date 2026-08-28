import 'dart:typed_data';

abstract interface class PrescriptionImageAcquirer {
  Future<PrescriptionImageAcquisitionOutcome> acquire(
    PrescriptionImageAcquisitionOptions options,
  );

  /// Releases owned resources, or returns false when the image needs no cleanup.
  Future<bool> release(AcquiredPrescriptionImage image);
}

class PrescriptionImageAcquisitionOptions {
  final bool allowCameraXFallback;
  final bool allowGalleryFallback;

  const PrescriptionImageAcquisitionOptions({
    this.allowCameraXFallback = true,
    this.allowGalleryFallback = true,
  });
}

enum PrescriptionImageAcquisitionSource {
  mlKitDocumentScanner,
  cameraXFallback,
  galleryFallback,
}

class PrescriptionScannerMetadata {
  final String mode;
  final String version;
  final int elapsedMilliseconds;

  const PrescriptionScannerMetadata({
    required this.mode,
    required this.version,
    required this.elapsedMilliseconds,
  });
}

class AcquiredPrescriptionImage {
  final Uint8List? bytes;
  final String? cachePath;
  final String filename;
  final String mimeType;
  final int width;
  final int height;
  final int byteSize;
  final PrescriptionImageAcquisitionSource source;
  final PrescriptionScannerMetadata scannerMetadata;

  AcquiredPrescriptionImage({
    this.bytes,
    this.cachePath,
    required this.filename,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.byteSize,
    required this.source,
    required this.scannerMetadata,
  }) {
    if ((bytes == null) == (cachePath == null)) {
      throw ArgumentError(
        'Exactly one of bytes and cachePath must be provided.',
      );
    }
  }
}

sealed class PrescriptionImageAcquisitionOutcome {
  const PrescriptionImageAcquisitionOutcome();
}

final class PrescriptionImageAcquisitionSuccess
    extends PrescriptionImageAcquisitionOutcome {
  final AcquiredPrescriptionImage image;

  const PrescriptionImageAcquisitionSuccess(this.image);
}

final class PrescriptionImageAcquisitionCancelled
    extends PrescriptionImageAcquisitionOutcome {
  const PrescriptionImageAcquisitionCancelled();
}

final class PrescriptionImageAcquisitionUnsupported
    extends PrescriptionImageAcquisitionOutcome {
  final PrescriptionImageAcquisitionFailureCode code;
  final Set<PrescriptionImageAcquisitionSource> eligibleFallbackSources;
  final String? message;

  const PrescriptionImageAcquisitionUnsupported({
    required this.code,
    this.eligibleFallbackSources = const {},
    this.message,
  });

  bool get canFallback => eligibleFallbackSources.isNotEmpty;

  bool isFallbackEligible(PrescriptionImageAcquisitionSource source) =>
      eligibleFallbackSources.contains(source);
}

final class PrescriptionImageAcquisitionFailure
    extends PrescriptionImageAcquisitionOutcome {
  final PrescriptionImageAcquisitionFailureCode code;
  final String? message;

  const PrescriptionImageAcquisitionFailure({required this.code, this.message});
}

enum PrescriptionImageAcquisitionFailureCode {
  unsupportedDevice('unsupported_device'),
  googlePlayServicesUnavailable('google_play_services_unavailable'),
  permissionDenied('permission_denied'),
  acquisitionInProgress('acquisition_in_progress'),
  invalidResult('invalid_result'),
  cacheFileUnavailable('cache_file_unavailable'),
  fileTooLarge('file_too_large'),
  unknown('unknown');

  final String value;

  const PrescriptionImageAcquisitionFailureCode(this.value);
}
