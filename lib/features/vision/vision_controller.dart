import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import 'detection_result.dart';
import 'image_processor.dart';

class VisionController extends ChangeNotifier with WidgetsBindingObserver {
  CameraController? controller;
  bool isInitialized = false;
  String? errorMessage;

  bool _isInitializing = false;
  bool _isRequestingPermission = false;
  DateTime? _startLoadingTime;

  final Random _random = Random();
  Timer? _mockTimer;

  List<DetectionResult> results = [];

  // ===== CAMERA CONTROL =====
  bool isTorchOn = false;
  bool isOverlayVisible = true;

  // ===== PERMISSION STATE =====
  bool isPermissionDenied = false;
  bool isPermissionPermanentlyDenied = false;

  // ===== PCD STATE =====
  bool isGrayscale = false;
  bool isNoiseEnabled = false;
  bool isEdgeDetectionEnabled = false;
  bool isBinaryEnabled = false;

  double contrast = 1.0;
  double brightness = 0.0;
  double blur = 0.0;
  double sharpen = 0.0;
  double binaryThreshold = 128.0;

  // ===== PANEL STATE =====
  bool isPcdPanelVisible = false;

  VisionController() {
    WidgetsBinding.instance.addObserver(this);
    initCamera();
  }

  Future<void> initCamera({bool skipPermissionRequest = false}) async {
    if (_isInitializing || _isRequestingPermission) return;

    _isInitializing = true;
    _startLoadingTime = DateTime.now();

    isInitialized = false;
    errorMessage = null;
    notifyListeners();

    try {
      PermissionStatus permissionStatus = await Permission.camera.status;

      if (!permissionStatus.isGranted && !skipPermissionRequest) {
        _isRequestingPermission = true;
        permissionStatus = await Permission.camera.request();
        _isRequestingPermission = false;
      }

      if (!permissionStatus.isGranted) {
        _applyPermissionState(permissionStatus);
        return;
      }

      isPermissionDenied = false;
      isPermissionPermanentlyDenied = false;
      errorMessage = null;

      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        errorMessage = 'No camera detected on device.';
        isInitialized = false;
        return;
      }

      await _disposeCameraOnly();

      controller = CameraController(
        cameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller!.initialize();

      final elapsed = DateTime.now().difference(_startLoadingTime!);
      if (elapsed.inMilliseconds < 500) {
        await Future.delayed(
          Duration(milliseconds: 500 - elapsed.inMilliseconds),
        );
      }

      isInitialized = true;
      errorMessage = null;
      isTorchOn = false;

      _startMockDetection();
    } catch (e) {
      errorMessage = 'Failed to initialize camera: $e';
      isInitialized = false;
    } finally {
      _isInitializing = false;
      _isRequestingPermission = false;
      notifyListeners();
    }
  }

  void _applyPermissionState(PermissionStatus status) {
    isInitialized = false;
    isPermissionDenied = true;
    isPermissionPermanentlyDenied = status.isPermanentlyDenied;
    errorMessage = 'No Camera Access';
    notifyListeners();
  }

  Future<void> openAppSettingsPage() async {
    await openAppSettings();
  }

  void _startMockDetection() {
    _mockTimer?.cancel();
    _generateMockDetection();

    _mockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _generateMockDetection();
    });
  }

  void _generateMockDetection() {
    final double rawX = 0.10 + (_random.nextDouble() * 0.55);
    final double rawY = 0.15 + (_random.nextDouble() * 0.45);
    final double rawW = 0.20 + (_random.nextDouble() * 0.15);
    final double rawH = 0.12 + (_random.nextDouble() * 0.10);

    const labels = ['D40 POTHOLE', 'D00 LONG CRACK', 'D20 ALLIGATOR'];
    final label = labels[_random.nextInt(labels.length)];
    final score = 0.80 + (_random.nextDouble() * 0.18);

    results = [
      DetectionResult(
        box: Rect.fromLTWH(rawX, rawY, rawW, rawH),
        label: label,
        score: score,
      ),
    ];

    notifyListeners();
  }

  Future<void> toggleTorch() async {
    final cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    try {
      if (isTorchOn) {
        await cameraController.setFlashMode(FlashMode.off);
        isTorchOn = false;
      } else {
        await cameraController.setFlashMode(FlashMode.torch);
        isTorchOn = true;
      }
      notifyListeners();
    } catch (e) {
      errorMessage = 'Failed to toggle torch: $e';
      notifyListeners();
    }
  }

  void toggleOverlay(bool value) {
    isOverlayVisible = value;
    notifyListeners();
  }

  void togglePcdPanel() {
    isPcdPanelVisible = !isPcdPanelVisible;
    notifyListeners();
  }

  void toggleGrayscale() {
    isGrayscale = !isGrayscale;
    notifyListeners();
  }

  void toggleNoise() {
    isNoiseEnabled = !isNoiseEnabled;
    notifyListeners();
  }

  void toggleEdgeDetection() {
    isEdgeDetectionEnabled = !isEdgeDetectionEnabled;
    notifyListeners();
  }

  void toggleBinary() {
    isBinaryEnabled = !isBinaryEnabled;
    notifyListeners();
  }

  void setContrast(double value) {
    contrast = value;
    notifyListeners();
  }

  void setBrightness(double value) {
    brightness = value;
    notifyListeners();
  }

  void setBlur(double value) {
    blur = value;
    notifyListeners();
  }

  void setSharpen(double value) {
    sharpen = value;
    notifyListeners();
  }

  void setBinaryThreshold(double value) {
    binaryThreshold = value;
    notifyListeners();
  }

  void resetPcd() {
    isGrayscale = false;
    isNoiseEnabled = false;
    isEdgeDetectionEnabled = false;
    isBinaryEnabled = false;

    contrast = 1.0;
    brightness = 0.0;
    blur = 0.0;
    sharpen = 0.0;
    binaryThreshold = 128.0;

    notifyListeners();
  }

  Future<String?> captureImage() async {
    final cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return null;
    }

    try {
      // Simpan status torch saat tombol capture ditekan
      final bool wasTorchOn = isTorchOn;

      // Ambil gambar dulu saat torch masih menyala
      final XFile file = await cameraController.takePicture();

      // Setelah foto berhasil diambil, baru matikan torch
      if (wasTorchOn) {
        try {
          await cameraController.setFlashMode(FlashMode.off);
        } catch (_) {
          // Abaikan kalau device tidak merespons tepat setelah capture
        }
        isTorchOn = false;
        notifyListeners();
      }

      final imagePath = await _applyFilters(file.path);
      return imagePath;
    } catch (e) {
      errorMessage = 'Failed to capture image: $e';
      notifyListeners();
      return null;
    }
  }

  Future<String> _applyFilters(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode captured image.');
    }

    final processed = image.clone();

    final shouldGrayscaleFirst =
        isGrayscale || isEdgeDetectionEnabled || isBinaryEnabled;

    if (shouldGrayscaleFirst) {
      img.grayscale(processed);
    }

    if (contrast != 1.0 || brightness != 0.0) {
      final brightnessScalar = (1.0 + brightness).clamp(0.0, 2.0);
      img.adjustColor(
        processed,
        contrast: contrast,
        brightness: brightnessScalar,
      );
    }

    if (blur > 0) {
      final radius = blur.round().clamp(1, 20);
      img.gaussianBlur(processed, radius: radius);
    }

    if (sharpen > 0) {
      applySharpen(processed, amount: sharpen);
    }

    if (isNoiseEnabled) {
      applyNoise(processed);
    }

    if (isEdgeDetectionEnabled) {
      applyEdgeDetection(processed);
    }

    if (isBinaryEnabled) {
      applyBinary(
        processed,
        threshold: binaryThreshold.round(),
      );
    }

    final filteredPath = '${imagePath}_processed.png';
    await File(filteredPath).writeAsBytes(img.encodePng(processed));

    return filteredPath;
  }

  Future<void> _disposeCameraOnly() async {
    final cameraController = controller;
    if (cameraController == null) return;

    try {
      await cameraController.setFlashMode(FlashMode.off);
    } catch (_) {}

    try {
      await cameraController.dispose();
    } catch (_) {}

    controller = null;
    isTorchOn = false;
  }

  Future<void> _handleResume() async {
    if (_isInitializing || _isRequestingPermission) return;

    final status = await Permission.camera.status;

    if (!status.isGranted) {
      isPermissionDenied = true;
      isPermissionPermanentlyDenied = status.isPermanentlyDenied;
      errorMessage = 'No Camera Access';
      isInitialized = false;
      notifyListeners();
      return;
    }

    if (controller == null || !isInitialized) {
      await initCamera(skipPermissionRequest: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isRequestingPermission) return;

    if (state == AppLifecycleState.resumed) {
      _handleResume();
      return;
    }

    final cameraController = controller;
    if (cameraController == null) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _mockTimer?.cancel();
      _disposeCameraOnly();
      isInitialized = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mockTimer?.cancel();
    _disposeCameraOnly();
    super.dispose();
  }
}