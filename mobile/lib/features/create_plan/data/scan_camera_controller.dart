import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Lifecycle state of the camera controller.
enum ScanCameraState {
  initializing,
  ready,
  capturing,
  unavailable,
  permissionDenied,
}

/// Manages the Flutter camera lifecycle for the scan screen.
///
/// Keeps all camera logic outside the widget body.
/// Dispose must be called when the screen leaves the tree.
@Deprecated('Thay thế bằng Google ML Kit Document Scanner trong ML Kit Flow mới')
class ScanCameraController extends ChangeNotifier {
  ScanCameraState _state = ScanCameraState.initializing;
  CameraController? _cameraController;
  String? _errorMessage;

  ScanCameraState get state => _state;
  CameraController? get cameraController => _cameraController;
  String? get errorMessage => _errorMessage;

  bool get isReady =>
      _state == ScanCameraState.ready &&
      _cameraController != null &&
      _cameraController!.value.isInitialized;

  /// Initialize and start live preview using the first back camera.
  Future<void> initialize() async {
    _setState(ScanCameraState.initializing);

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _errorMessage = 'Không tìm thấy camera trên thiết bị.';
        _setState(ScanCameraState.unavailable);
        return;
      }

      // Prefer back camera; fallback to first available.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );

      await controller.initialize();

      _cameraController = controller;
      _errorMessage = null;
      _setState(ScanCameraState.ready);
    } on CameraException catch (e) {
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted') {
        _errorMessage =
            'Quyền camera bị từ chối. Vui lòng cấp quyền trong Cài đặt.';
        _setState(ScanCameraState.permissionDenied);
      } else {
        _errorMessage = 'Không thể khởi động camera: ${e.description}';
        _setState(ScanCameraState.unavailable);
      }
    } catch (e) {
      _errorMessage = 'Lỗi camera không xác định: $e';
      _setState(ScanCameraState.unavailable);
    }
  }

  /// Capture a single frame from the live preview.
  /// Returns JPEG bytes or null if capture failed.
  Future<Uint8List?> capturePhoto() async {
    if (!isReady) return null;
    _setState(ScanCameraState.capturing);
    try {
      final xfile = await _cameraController!.takePicture();
      final bytes = await xfile.readAsBytes();
      _setState(ScanCameraState.ready);
      return bytes;
    } catch (e) {
      _errorMessage = 'Chụp ảnh thất bại: $e';
      _setState(ScanCameraState.ready);
      return null;
    }
  }

  /// Called when the app is paused (e.g. home button pressed).
  Future<void> pause() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _cameraController!.pausePreview();
    }
  }

  /// Called when the app is resumed.
  Future<void> resume() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _cameraController!.resumePreview();
    }
  }

  void _setState(ScanCameraState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_cameraController?.value.isStreamingImages == true) {
      _cameraController?.stopImageStream();
    }
    _cameraController?.dispose();
    super.dispose();
  }
}
