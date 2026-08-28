import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/features/create_plan/domain/prescription_image_acquirer.dart';

class _FakePrescriptionImageAcquirer implements PrescriptionImageAcquirer {
  _FakePrescriptionImageAcquirer(this.nextOutcome);

  PrescriptionImageAcquisitionOutcome nextOutcome;
  int callCount = 0;
  PrescriptionImageAcquisitionOptions? lastOptions;
  AcquiredPrescriptionImage? lastReleasedImage;

  @override
  Future<PrescriptionImageAcquisitionOutcome> acquire(
    PrescriptionImageAcquisitionOptions options,
  ) async {
    callCount += 1;
    lastOptions = options;
    return nextOutcome;
  }

  @override
  Future<bool> release(AcquiredPrescriptionImage image) async {
    lastReleasedImage = image;
    return true;
  }
}

void main() {
  group('PrescriptionImageAcquirer', () {
    test('returns image and scanner metadata on success', () async {
      final image = AcquiredPrescriptionImage(
        bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
        filename: 'prescription.jpg',
        mimeType: 'image/jpeg',
        width: 1200,
        height: 1600,
        byteSize: 4,
        source: PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
        scannerMetadata: const PrescriptionScannerMetadata(
          mode: 'full',
          version: '16.0.0',
          elapsedMilliseconds: 842,
        ),
      );
      final fake = _FakePrescriptionImageAcquirer(
        PrescriptionImageAcquisitionSuccess(image),
      );
      const options = PrescriptionImageAcquisitionOptions(
        allowCameraXFallback: true,
        allowGalleryFallback: false,
      );

      final outcome = await fake.acquire(options);

      expect(fake.callCount, 1);
      expect(fake.lastOptions, same(options));
      expect(outcome, isA<PrescriptionImageAcquisitionSuccess>());
      final success = outcome as PrescriptionImageAcquisitionSuccess;
      expect(
        success.image.source,
        PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
      );
      expect(success.image.bytes, [0xff, 0xd8, 0xff, 0xd9]);
      expect(success.image.cachePath, isNull);
      expect(success.image.scannerMetadata.mode, 'full');
      expect(success.image.scannerMetadata.version, '16.0.0');
      expect(success.image.scannerMetadata.elapsedMilliseconds, 842);

      expect(await fake.release(success.image), true);
      expect(fake.lastReleasedImage, same(success.image));
    });

    test('represents user cancellation without a failure', () async {
      final fake = _FakePrescriptionImageAcquirer(
        const PrescriptionImageAcquisitionCancelled(),
      );

      final outcome = await fake.acquire(
        const PrescriptionImageAcquisitionOptions(),
      );

      expect(outcome, isA<PrescriptionImageAcquisitionCancelled>());
      expect(outcome, isNot(isA<PrescriptionImageAcquisitionFailure>()));
    });

    test('unsupported result identifies eligible fallback sources', () async {
      final fake = _FakePrescriptionImageAcquirer(
        const PrescriptionImageAcquisitionUnsupported(
          code: PrescriptionImageAcquisitionFailureCode.unsupportedDevice,
          eligibleFallbackSources: {
            PrescriptionImageAcquisitionSource.cameraXFallback,
            PrescriptionImageAcquisitionSource.galleryFallback,
          },
        ),
      );

      final outcome = await fake.acquire(
        const PrescriptionImageAcquisitionOptions(),
      );

      final unsupported = outcome as PrescriptionImageAcquisitionUnsupported;
      expect(unsupported.canFallback, true);
      expect(
        unsupported.isFallbackEligible(
          PrescriptionImageAcquisitionSource.cameraXFallback,
        ),
        true,
      );
      expect(
        unsupported.isFallbackEligible(
          PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
        ),
        false,
      );
    });

    test('failure exposes a stable failure code', () async {
      final fake = _FakePrescriptionImageAcquirer(
        const PrescriptionImageAcquisitionFailure(
          code: PrescriptionImageAcquisitionFailureCode.permissionDenied,
          message: 'Camera permission was denied',
        ),
      );

      final outcome = await fake.acquire(
        const PrescriptionImageAcquisitionOptions(),
      );

      final failure = outcome as PrescriptionImageAcquisitionFailure;
      expect(
        failure.code,
        PrescriptionImageAcquisitionFailureCode.permissionDenied,
      );
      expect(failure.code.value, 'permission_denied');
      expect(failure.message, 'Camera permission was denied');
    });
  });

  group('AcquiredPrescriptionImage invariant', () {
    test('accepts exactly one of bytes and cachePath', () {
      expect(
        () => AcquiredPrescriptionImage(
          bytes: Uint8List(1),
          filename: 'bytes.jpg',
          mimeType: 'image/jpeg',
          width: 1,
          height: 1,
          byteSize: 1,
          source: PrescriptionImageAcquisitionSource.galleryFallback,
          scannerMetadata: const PrescriptionScannerMetadata(
            mode: 'gallery',
            version: 'image_picker',
            elapsedMilliseconds: 1,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => AcquiredPrescriptionImage(
          cachePath: '/cache/prescription.jpg',
          filename: 'path.jpg',
          mimeType: 'image/jpeg',
          width: 1,
          height: 1,
          byteSize: 1,
          source: PrescriptionImageAcquisitionSource.cameraXFallback,
          scannerMetadata: const PrescriptionScannerMetadata(
            mode: 'camera',
            version: 'camerax',
            elapsedMilliseconds: 1,
          ),
        ),
        returnsNormally,
      );
      expect(
        () => AcquiredPrescriptionImage(
          filename: 'missing.jpg',
          mimeType: 'image/jpeg',
          width: 1,
          height: 1,
          byteSize: 1,
          source: PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
          scannerMetadata: const PrescriptionScannerMetadata(
            mode: 'full',
            version: '16.0.0',
            elapsedMilliseconds: 1,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => AcquiredPrescriptionImage(
          bytes: Uint8List(1),
          cachePath: '/cache/duplicate.jpg',
          filename: 'duplicate.jpg',
          mimeType: 'image/jpeg',
          width: 1,
          height: 1,
          byteSize: 1,
          source: PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
          scannerMetadata: const PrescriptionScannerMetadata(
            mode: 'full',
            version: '16.0.0',
            elapsedMilliseconds: 1,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
