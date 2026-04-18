import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'damage_painter.dart';
import 'processing_view.dart';
import 'vision_controller.dart';

class VisionView extends StatefulWidget {
  const VisionView({super.key});

  @override
  State<VisionView> createState() => _VisionViewState();
}

class _VisionViewState extends State<VisionView> {
  late VisionController _visionController;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _visionController = VisionController();
  }

  @override
  void dispose() {
    _visionController.dispose();
    super.dispose();
  }

  void _showPrettySnackBar(String message) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        width: screenWidth * 0.88,
        backgroundColor: const Color(0xFF1F2A44),
        elevation: 8,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Future<void> _captureAndOpenProcessing() async {
    final imagePath = await _visionController.captureImage();

    if (!mounted) return;

    if (imagePath == null) {
      _showPrettySnackBar('Gagal mengambil gambar.');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingView(imagePath: imagePath),
      ),
    );
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (!mounted || pickedFile == null) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessingView(imagePath: pickedFile.path),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showPrettySnackBar('Gagal mengambil gambar dari galeri.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart-Patrol Vision'),
      ),
      body: ListenableBuilder(
        listenable: _visionController,
        builder: (context, child) {
          if (_visionController.isPermissionDenied) {
            return _buildNoCameraAccessState();
          }

          if (_visionController.errorMessage != null &&
              !_visionController.isInitialized) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _visionController.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            );
          }

          if (!_visionController.isInitialized ||
              _visionController.controller == null) {
            return _buildLoadingState();
          }

          return _buildVisionPreview();
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 18),
            Text(
              'Menghubungkan ke Sensor Visual...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2A44),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Mohon tunggu sebentar, kamera sedang diinisialisasi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF4A5A7A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCameraAccessState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.no_photography_rounded,
                  size: 38,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No Camera Access',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1F2A44),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Aplikasi membutuhkan izin kamera untuk menjalankan fitur Smart-Patrol Vision.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: Color(0xFF4A5A7A),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  await _visionController.openAppSettingsPage();
                },
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Open Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDCE4FF),
                  foregroundColor: const Color(0xFF1F2A44),
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

  Widget _buildVisionPreview() {
    final CameraController cameraController = _visionController.controller!;
    final double previewAspectRatio = 1 / cameraController.value.aspectRatio;

    Widget preview = CameraPreview(cameraController);

    preview = ColorFiltered(
      colorFilter: ColorFilter.matrix([
        _visionController.contrast,
        0,
        0,
        0,
        _visionController.brightness * 255,
        0,
        _visionController.contrast,
        0,
        0,
        _visionController.brightness * 255,
        0,
        0,
        _visionController.contrast,
        0,
        _visionController.brightness * 255,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: preview,
    );

    if (_visionController.isGrayscale) {
      preview = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: preview,
      );
    }

    if (_visionController.blur > 0) {
      preview = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: _visionController.blur,
          sigmaY: _visionController.blur,
        ),
        child: preview,
      );
    }

    return Container(
      color: const Color(0xFFF6F8FF),
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: previewAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            preview,

            if (_visionController.isOverlayVisible)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: DamagePainter(
                      results: _visionController.results,
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 14,
              left: 12,
              right: 12,
              child: _buildTopControlBar(),
            ),

            if (_visionController.isPcdPanelVisible)
              Positioned(
                bottom: 110,
                left: 16,
                right: 16,
                child: _buildPcdSliderPanel(),
              ),

            Positioned(
              bottom: 28,
              right: 24,
              child: GestureDetector(
                onTap: _pickImageFromGallery,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.96),
                    border: Border.all(
                      color: const Color(0xFF1F2A44),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: Color(0xFF1F2A44),
                    size: 24,
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _captureAndOpenProcessing,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.96),
                      border: Border.all(
                        color: const Color(0xFF1F2A44),
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Color(0xFF1F2A44),
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTopActionChip(
              icon: _visionController.isTorchOn
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
              label: 'Torch',
              onTap: () async {
                await _visionController.toggleTorch();
              },
            ),
          ),
          Expanded(
            child: _buildTopActionChip(
              icon: _visionController.isOverlayVisible
                  ? Icons.layers_rounded
                  : Icons.layers_clear_rounded,
              label: 'Overlay',
              onTap: () {
                _visionController.toggleOverlay(
                  !_visionController.isOverlayVisible,
                );
              },
            ),
          ),
          Expanded(
            child: _buildTopActionChip(
              icon: _visionController.isGrayscale
                  ? Icons.contrast_rounded
                  : Icons.filter_b_and_w_rounded,
              label: 'Gray',
              onTap: () {
                _visionController.toggleGrayscale();
              },
            ),
          ),
          Expanded(
            child: _buildTopActionChip(
              icon: _visionController.isPcdPanelVisible
                  ? Icons.tune_rounded
                  : Icons.tune_outlined,
              label: 'PCD',
              onTap: () {
                _visionController.togglePcdPanel();
              },
            ),
          ),
          Expanded(
            child: _buildTopActionChip(
              icon: Icons.refresh_rounded,
              label: 'Reset',
              onTap: () {
                _visionController.resetPcd();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPcdSliderPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.40),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSliderRow(
            title: 'Contrast',
            valueText: _visionController.contrast.toStringAsFixed(2),
            slider: Slider(
              value: _visionController.contrast,
              min: 0.5,
              max: 2.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: _visionController.setContrast,
            ),
          ),
          _buildSliderRow(
            title: 'Brightness',
            valueText: _visionController.brightness.toStringAsFixed(2),
            slider: Slider(
              value: _visionController.brightness,
              min: -1.0,
              max: 1.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: _visionController.setBrightness,
            ),
          ),
          _buildSliderRow(
            title: 'Blur',
            valueText: _visionController.blur.toStringAsFixed(1),
            slider: Slider(
              value: _visionController.blur,
              min: 0.0,
              max: 5.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: _visionController.setBlur,
            ),
          ),
          _buildSliderRow(
            title: 'Sharpen',
            valueText: _visionController.sharpen.toStringAsFixed(1),
            slider: Slider(
              value: _visionController.sharpen,
              min: 0.0,
              max: 3.0,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: _visionController.setSharpen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String title,
    required String valueText,
    required Widget slider,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            Text(
              valueText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        slider,
      ],
    );
  }
}