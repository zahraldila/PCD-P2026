import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';

import 'image_processor.dart';

class ProcessingView extends StatefulWidget {
  final String imagePath;

  const ProcessingView({
    super.key,
    required this.imagePath,
  });

  @override
  State<ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<ProcessingView> {
  bool isGrayscale = false;
  bool isNoiseEnabled = false;
  bool isEdgeDetectionEnabled = false;
  bool isBinaryEnabled = false;

  double contrast = 1.0;
  double brightness = 0.0;
  double blur = 0.0;
  double sharpen = 0.0;
  double binaryThreshold = 128.0;

  HistogramResult? histogramResult;

  bool isImageLoading = true;
  bool isHistogramLoading = true;
  bool isSavingToGallery = false;

  img.Image? _originalImage;
  Uint8List? _processedImageBytes;
  int _processingRequestId = 0;

  @override
  void initState() {
    super.initState();
    _initializeImage();
  }

  Future<void> _initializeImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (!mounted) return;

      if (decoded == null) {
        setState(() {
          isImageLoading = false;
          isHistogramLoading = false;
        });
        return;
      }

      if (decoded.width > 1080) {
        _originalImage = img.copyResize(decoded, width: 1080);
      } else {
        _originalImage = decoded;
      }

      await _applyProcessing();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isImageLoading = false;
        isHistogramLoading = false;
      });
    }
  }

  Future<void> _applyProcessing() async {
    final original = _originalImage;
    if (original == null) return;

    final int requestId = ++_processingRequestId;

    if (mounted) {
      setState(() {
        isImageLoading = true;
        isHistogramLoading = true;
      });
    }

    final processed = original.clone();

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

    final histogram = computeHistogramFromImage(processed);
    final bytes = Uint8List.fromList(img.encodePng(processed));

    if (!mounted || requestId != _processingRequestId) return;

    setState(() {
      _processedImageBytes = bytes;
      histogramResult = histogram;
      isImageLoading = false;
      isHistogramLoading = false;
    });
  }

  Future<bool> _requestGalleryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photosAddOnly.request();
      return status.isGranted || status.isLimited;
    }

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 29) {
        final status = await Permission.storage.request();
        return status.isGranted;
      }
      return true;
    }

    return true;
  }

  Future<void> _saveToGallery() async {
    if (_processedImageBytes == null || isSavingToGallery) return;

    setState(() {
      isSavingToGallery = true;
    });

    try {
      final hasPermission = await _requestGalleryPermission();

      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.fromLTRB(16, 0, 16, 20),
            content: Text('Izin galeri ditolak.'),
          ),
        );
        return;
      }

      final fileName = 'pcd_${DateTime.now().millisecondsSinceEpoch}.png';

      final result = await SaverGallery.saveImage(
        _processedImageBytes!,
        fileName: fileName,
        skipIfExists: false,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(
            result.isSuccess
                ? 'Gambar berhasil disimpan ke galeri.'
                : (result.errorMessage ?? 'Gagal menyimpan gambar ke galeri.'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text('Gagal menyimpan ke galeri: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSavingToGallery = false;
        });
      }
    }
  }

  void _resetAll() {
    setState(() {
      isGrayscale = false;
      isNoiseEnabled = false;
      isEdgeDetectionEnabled = false;
      isBinaryEnabled = false;

      contrast = 1.0;
      brightness = 0.0;
      blur = 0.0;
      sharpen = 0.0;
      binaryThreshold = 128.0;
    });

    _applyProcessing();
  }

  String _buildActiveFilterText() {
    final active = <String>[];

    if (isGrayscale) active.add('Grayscale');
    if (contrast != 1.0) active.add('Contrast');
    if (brightness != 0.0) active.add('Brightness');
    if (blur > 0.0) active.add('Blur');
    if (sharpen > 0.0) active.add('Sharpen');
    if (isNoiseEnabled) active.add('Noise');
    if (isEdgeDetectionEnabled) active.add('Edge Detection');
    if (isBinaryEnabled) active.add('Binary');

    if (active.isEmpty) return 'PCD: Natural';
    return 'PCD: ${active.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final Widget processedImageWidget = _processedImageBytes != null
        ? Image.memory(
            _processedImageBytes!,
            fit: BoxFit.contain,
          )
        : const Center(
            child: Text(
              'Gambar tidak tersedia.',
              style: TextStyle(color: Color(0xFF4A5A7A)),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('PCD Processing'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FF),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: isImageLoading
                    ? const Center(
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      )
                    : processedImageWidget,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _buildActiveFilterText(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2A44),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildHistogramCard(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: isGrayscale
                              ? Icons.filter_b_and_w_rounded
                              : Icons.contrast_rounded,
                          label: isGrayscale ? 'Grayscale ON' : 'Grayscale',
                          onTap: () {
                            setState(() {
                              isGrayscale = !isGrayscale;
                            });
                            _applyProcessing();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionButton(
                          icon: isNoiseEnabled
                              ? Icons.grain
                              : Icons.grain_outlined,
                          label: isNoiseEnabled ? 'Noise ON' : 'Noise',
                          onTap: () {
                            setState(() {
                              isNoiseEnabled = !isNoiseEnabled;
                            });
                            _applyProcessing();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: isEdgeDetectionEnabled
                              ? Icons.auto_fix_high
                              : Icons.auto_fix_off,
                          label: isEdgeDetectionEnabled ? 'Edge ON' : 'Edge',
                          onTap: () {
                            setState(() {
                              isEdgeDetectionEnabled =
                                  !isEdgeDetectionEnabled;
                            });
                            _applyProcessing();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionButton(
                          icon: isBinaryEnabled
                              ? Icons.blur_on
                              : Icons.blur_on_outlined,
                          label: isBinaryEnabled ? 'Binary ON' : 'Binary',
                          onTap: () {
                            setState(() {
                              isBinaryEnabled = !isBinaryEnabled;
                            });
                            _applyProcessing();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.save_alt_rounded,
                          label:
                              isSavingToGallery ? 'Saving...' : 'Save Gallery',
                          onTap: isSavingToGallery ? () {} : _saveToGallery,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.refresh_rounded,
                          label: 'Reset',
                          onTap: _resetAll,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildSliderRow(
                    title: 'Contrast',
                    valueText: contrast.toStringAsFixed(2),
                    slider: Slider(
                      value: contrast,
                      min: 0.5,
                      max: 2.0,
                      onChanged: (value) {
                        setState(() {
                          contrast = value;
                        });
                      },
                      onChangeEnd: (_) {
                        _applyProcessing();
                      },
                    ),
                  ),
                  _buildSliderRow(
                    title: 'Brightness',
                    valueText: brightness.toStringAsFixed(2),
                    slider: Slider(
                      value: brightness,
                      min: -1.0,
                      max: 1.0,
                      onChanged: (value) {
                        setState(() {
                          brightness = value;
                        });
                      },
                      onChangeEnd: (_) {
                        _applyProcessing();
                      },
                    ),
                  ),
                  _buildSliderRow(
                    title: 'Blur',
                    valueText: blur.toStringAsFixed(1),
                    slider: Slider(
                      value: blur,
                      min: 0.0,
                      max: 5.0,
                      onChanged: (value) {
                        setState(() {
                          blur = value;
                        });
                      },
                      onChangeEnd: (_) {
                        _applyProcessing();
                      },
                    ),
                  ),
                  _buildSliderRow(
                    title: 'Sharpen',
                    valueText: sharpen.toStringAsFixed(1),
                    slider: Slider(
                      value: sharpen,
                      min: 0.0,
                      max: 3.0,
                      onChanged: (value) {
                        setState(() {
                          sharpen = value;
                        });
                      },
                      onChangeEnd: (_) {
                        _applyProcessing();
                      },
                    ),
                  ),
                  _buildSliderRow(
                    title: 'Binary Threshold',
                    valueText: binaryThreshold.toStringAsFixed(0),
                    slider: Slider(
                      value: binaryThreshold,
                      min: 0.0,
                      max: 255.0,
                      onChanged: (value) {
                        setState(() {
                          binaryThreshold = value;
                        });
                      },
                      onChangeEnd: (_) {
                        if (isBinaryEnabled) {
                          _applyProcessing();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistogramCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: isHistogramLoading
          ? const Column(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 12),
                Text(
                  'Menghitung histogram...',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2A44),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Histogram',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2A44),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Luma avg: ${histogramResult?.averageLuma.toStringAsFixed(0) ?? '-'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A5A7A),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 120,
                  child: _buildHistogramBars(),
                ),
              ],
            ),
    );
  }

  Widget _buildHistogramBars() {
    final bins = histogramResult?.bins ?? [];
    if (bins.isEmpty) {
      return const Center(
        child: Text(
          'Histogram tidak tersedia.',
          style: TextStyle(color: Color(0xFF4A5A7A)),
        ),
      );
    }

    const int groupedBars = 64;
    final int groupSize = (bins.length / groupedBars).ceil();

    final grouped = <double>[];
    for (int i = 0; i < bins.length; i += groupSize) {
      final slice = bins.sublist(
        i,
        (i + groupSize > bins.length) ? bins.length : i + groupSize,
      );
      final sum = slice.fold<int>(0, (prev, e) => prev + e);
      grouped.add(sum.toDouble());
    }

    final groupedMax = grouped.reduce((a, b) => a > b ? a : b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: grouped.map((value) {
        final normalized = groupedMax == 0 ? 0.0 : value / groupedMax;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: normalized * 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF5877B8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFDCE4FF),
        foregroundColor: const Color(0xFF1F2A44),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                  color: Color(0xFF1F2A44),
                ),
              ),
            ),
            Text(
              valueText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A5A7A),
              ),
            ),
          ],
        ),
        slider,
      ],
    );
  }
}