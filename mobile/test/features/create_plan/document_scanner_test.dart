import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_app/features/create_plan/data/ml_kit_prescription_image_acquirer.dart';
import 'package:medicine_app/features/create_plan/domain/prescription_image_acquirer.dart';

class _FakeScannerChannel implements PrescriptionDocumentScannerChannel {
  Object? nextResult;
  Completer<Object?>? pendingResult;
  final List<bool> galleryImportValues = [];
  final List<String> releasedPaths = [];
  bool releaseResult = true;

  @override
  Future<Object?> scan({required bool allowGalleryImport}) {
    galleryImportValues.add(allowGalleryImport);
    final pending = pendingResult;
    return pending?.future ?? Future<Object?>.value(nextResult);
  }

  @override
  Future<bool> release({required String cachePath}) async {
    releasedPaths.add(cachePath);
    return releaseResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('method channel uses the locked scanner wire contract', () async {
    const methodChannel = MethodChannel(
      MethodChannelPrescriptionDocumentScanner.channelName,
    );
    final receivedCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          receivedCalls.add(call);
          return call.method == 'releasePrescriptionDocument'
              ? true
              : {'status': 'cancelled'};
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    final response = await const MethodChannelPrescriptionDocumentScanner(
      channel: methodChannel,
    ).scan(allowGalleryImport: false);
    final released = await const MethodChannelPrescriptionDocumentScanner(
      channel: methodChannel,
    ).release(cachePath: '/internal/cache/prescription_scan_1.jpg');

    expect(receivedCalls[0].method, 'scanPrescriptionDocument');
    expect(receivedCalls[0].arguments, {'allow_gallery_import': false});
    expect(receivedCalls[1].method, 'releasePrescriptionDocument');
    expect(receivedCalls[1].arguments, {
      'cache_path': '/internal/cache/prescription_scan_1.jpg',
    });
    expect(response, {'status': 'cancelled'});
    expect(released, true);
  });

  group('MlKitPrescriptionImageAcquirer', () {
    test('maps a native cache JPEG into the WP-04 success outcome', () async {
      final channel = _FakeScannerChannel()
        ..nextResult = {
          'status': 'success',
          'cache_path':
              '/data/user/0/app/cache/prescription_scans/prescription_scan_ok.jpg',
          'filename': 'prescription.jpg',
          'mime_type': 'image/jpeg',
          'width': 1200,
          'height': 1600,
          'byte_size': 4096,
          'scanner_mode': 'full',
          'scanner_version': '16.0.0',
          'elapsed_milliseconds': 812,
        };
      final acquirer = MlKitPrescriptionImageAcquirer(channel: channel);

      final outcome = await acquirer.acquire(
        const PrescriptionImageAcquisitionOptions(allowGalleryFallback: true),
      );

      expect(channel.galleryImportValues, [true]);
      final image = (outcome as PrescriptionImageAcquisitionSuccess).image;
      expect(image.bytes, isNull);
      expect(
        image.cachePath,
        '/data/user/0/app/cache/prescription_scans/prescription_scan_ok.jpg',
      );
      expect(image.filename, 'prescription.jpg');
      expect(image.mimeType, 'image/jpeg');
      expect(
        image.source,
        PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
      );
      expect(image.scannerMetadata.mode, 'full');
      expect(image.scannerMetadata.version, '16.0.0');
      expect(image.scannerMetadata.elapsedMilliseconds, 812);
    });

    test(
      'disables ML Kit gallery import when gallery is not allowed',
      () async {
        final channel = _FakeScannerChannel()
          ..nextResult = {'status': 'cancelled'};
        final acquirer = MlKitPrescriptionImageAcquirer(channel: channel);

        await acquirer.acquire(
          const PrescriptionImageAcquisitionOptions(
            allowGalleryFallback: false,
          ),
        );

        expect(channel.galleryImportValues, [false]);
      },
    );

    test('maps cancellation without treating it as a failure', () async {
      final channel = _FakeScannerChannel()
        ..nextResult = {'status': 'cancelled'};

      final outcome = await MlKitPrescriptionImageAcquirer(
        channel: channel,
      ).acquire(const PrescriptionImageAcquisitionOptions());

      expect(outcome, isA<PrescriptionImageAcquisitionCancelled>());
    });

    test(
      'derives unsupported fallback eligibility from acquisition options',
      () async {
        final channel = _FakeScannerChannel()
          ..nextResult = {
            'status': 'unsupported',
            'code': 'google_play_services_unavailable',
            'message': 'Document scanner is unavailable.',
          };

        final outcome = await MlKitPrescriptionImageAcquirer(channel: channel)
            .acquire(
              const PrescriptionImageAcquisitionOptions(
                allowCameraXFallback: true,
                allowGalleryFallback: false,
              ),
            );

        final unsupported = outcome as PrescriptionImageAcquisitionUnsupported;
        expect(
          unsupported.code,
          PrescriptionImageAcquisitionFailureCode.googlePlayServicesUnavailable,
        );
        expect(unsupported.eligibleFallbackSources, {
          PrescriptionImageAcquisitionSource.cameraXFallback,
        });
      },
    );

    test('maps stable native failure codes', () async {
      final channel = _FakeScannerChannel()
        ..nextResult = {
          'status': 'failure',
          'code': 'cache_file_unavailable',
          'message': 'Scanner output could not be cached.',
        };

      final outcome = await MlKitPrescriptionImageAcquirer(
        channel: channel,
      ).acquire(const PrescriptionImageAcquisitionOptions());

      final failure = outcome as PrescriptionImageAcquisitionFailure;
      expect(
        failure.code,
        PrescriptionImageAcquisitionFailureCode.cacheFileUnavailable,
      );
    });

    test('rejects a duplicate request while acquisition is pending', () async {
      final channel = _FakeScannerChannel()
        ..pendingResult = Completer<Object?>();
      final acquirer = MlKitPrescriptionImageAcquirer(channel: channel);

      final first = acquirer.acquire(
        const PrescriptionImageAcquisitionOptions(),
      );
      final duplicate = await acquirer.acquire(
        const PrescriptionImageAcquisitionOptions(),
      );

      final failure = duplicate as PrescriptionImageAcquisitionFailure;
      expect(
        failure.code,
        PrescriptionImageAcquisitionFailureCode.acquisitionInProgress,
      );
      expect(channel.galleryImportValues, [true]);

      channel.pendingResult!.complete({'status': 'cancelled'});
      await first;
    });

    test('rejects native success metadata over the 10 MB limit', () async {
      final channel = _FakeScannerChannel()
        ..nextResult = {
          'status': 'success',
          'cache_path':
              '/data/user/0/app/cache/prescription_scans/prescription_scan_large.jpg',
          'filename': 'prescription.jpg',
          'mime_type': 'image/jpeg',
          'width': 1200,
          'height': 1600,
          'byte_size': 10 * 1024 * 1024 + 1,
          'scanner_mode': 'full',
          'scanner_version': '16.0.0',
          'elapsed_milliseconds': 812,
        };

      final outcome = await MlKitPrescriptionImageAcquirer(
        channel: channel,
      ).acquire(const PrescriptionImageAcquisitionOptions());

      final failure = outcome as PrescriptionImageAcquisitionFailure;
      expect(
        failure.code,
        PrescriptionImageAcquisitionFailureCode.fileTooLarge,
      );
      expect(channel.releasedPaths, [
        '/data/user/0/app/cache/prescription_scans/prescription_scan_large.jpg',
      ]);
    });

    test(
      'releases an owned cache path from malformed success metadata',
      () async {
        final channel = _FakeScannerChannel()
          ..nextResult = {
            'status': 'success',
            'cache_path':
                '/data/user/0/app/cache/prescription_scans/prescription_scan_bad.jpg',
            'filename': 'prescription.jpg',
            'mime_type': 'image/png',
            'width': 1200,
            'height': 1600,
            'byte_size': 4096,
            'scanner_mode': 'full',
            'scanner_version': '16.0.0',
            'elapsed_milliseconds': 812,
          };

        final outcome = await MlKitPrescriptionImageAcquirer(
          channel: channel,
        ).acquire(const PrescriptionImageAcquisitionOptions());

        expect(
          (outcome as PrescriptionImageAcquisitionFailure).code,
          PrescriptionImageAcquisitionFailureCode.invalidResult,
        );
        expect(channel.releasedPaths, [
          '/data/user/0/app/cache/prescription_scans/prescription_scan_bad.jpg',
        ]);
      },
    );

    test('releases an owned ML Kit cache result through the bridge', () async {
      final channel = _FakeScannerChannel();
      final PrescriptionImageAcquirer acquirer = MlKitPrescriptionImageAcquirer(
        channel: channel,
      );
      final image = AcquiredPrescriptionImage(
        cachePath: '/internal/cache/prescription_scans/prescription_scan_1.jpg',
        filename: 'prescription.jpg',
        mimeType: 'image/jpeg',
        width: 1200,
        height: 1600,
        byteSize: 4096,
        source: PrescriptionImageAcquisitionSource.mlKitDocumentScanner,
        scannerMetadata: const PrescriptionScannerMetadata(
          mode: 'full',
          version: '16.0.0',
          elapsedMilliseconds: 700,
        ),
      );

      final released = await acquirer.release(image);

      expect(released, true);
      expect(channel.releasedPaths, [image.cachePath]);
    });

    test('safely ignores byte, CameraX, and gallery ownership', () async {
      final channel = _FakeScannerChannel();
      final PrescriptionImageAcquirer acquirer = MlKitPrescriptionImageAcquirer(
        channel: channel,
      );
      final images = [
        AcquiredPrescriptionImage(
          bytes: Uint8List(1),
          filename: 'scanner-bytes.jpg',
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
        AcquiredPrescriptionImage(
          cachePath: '/internal/cache/camerax.jpg',
          filename: 'camerax.jpg',
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
        AcquiredPrescriptionImage(
          bytes: Uint8List(1),
          filename: 'gallery.jpg',
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
      ];

      final released = await Future.wait(images.map(acquirer.release));

      expect(released, [false, false, false]);
      expect(channel.releasedPaths, isEmpty);
    });
  });
}
