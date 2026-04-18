import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

class HistogramResult {
  final List<int> bins;
  final double averageLuma;

  const HistogramResult({
    required this.bins,
    required this.averageLuma,
  });
}

Future<HistogramResult> computeHistogram(String path) async {
  final bytes = await File(path).readAsBytes();
  final decoded = img.decodeImage(bytes);

  if (decoded == null) {
    return const HistogramResult(
      bins: [],
      averageLuma: 0,
    );
  }

  return computeHistogramFromImage(decoded);
}

HistogramResult computeHistogramFromImage(img.Image image) {
  final histogram = List<int>.filled(256, 0);
  int totalLuma = 0;
  int totalPixels = 0;

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final luma = img.getLuminance(pixel).round().clamp(0, 255);

      histogram[luma]++;
      totalLuma += luma;
      totalPixels++;
    }
  }

  final avg = totalPixels == 0 ? 0.0 : totalLuma / totalPixels;

  return HistogramResult(
    bins: histogram,
    averageLuma: avg,
  );
}

void applyEdgeDetection(img.Image image) {
  final source = image.clone();

  const sobelX = [
    [-1, 0, 1],
    [-2, 0, 2],
    [-1, 0, 1],
  ];

  const sobelY = [
    [1, 2, 1],
    [0, 0, 0],
    [-1, -2, -1],
  ];

  for (int y = 1; y < source.height - 1; y++) {
    for (int x = 1; x < source.width - 1; x++) {
      int gx = 0;
      int gy = 0;

      for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
          final pixel = source.getPixel(x + kx, y + ky);
          final gray = img.getLuminance(pixel).round();

          gx += sobelX[ky + 1][kx + 1] * gray;
          gy += sobelY[ky + 1][kx + 1] * gray;
        }
      }

      final magnitude = sqrt((gx * gx + gy * gy).toDouble())
          .round()
          .clamp(0, 255);

      image.setPixelRgb(x, y, magnitude, magnitude, magnitude);
    }
  }
}

void applyNoise(img.Image image, {double noiseRatio = 0.02}) {
  final random = Random();

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      if (random.nextDouble() < noiseRatio) {
        if (random.nextBool()) {
          image.setPixelRgb(x, y, 255, 255, 255);
        } else {
          image.setPixelRgb(x, y, 0, 0, 0);
        }
      }
    }
  }
}

void applySharpen(img.Image image, {double amount = 1.0}) {
  if (amount <= 0) return;

  final source = image.clone();
  final center = 5.0 + (amount * 2.0);

  final kernel = <List<double>>[
    [0, -1, 0],
    [-1, center, -1],
    [0, -1, 0],
  ];

  for (int y = 1; y < image.height - 1; y++) {
    for (int x = 1; x < image.width - 1; x++) {
      double r = 0;
      double g = 0;
      double b = 0;

      for (int ky = -1; ky <= 1; ky++) {
        for (int kx = -1; kx <= 1; kx++) {
          final pixel = source.getPixel(x + kx, y + ky);
          final weight = kernel[ky + 1][kx + 1];

          r += pixel.r * weight;
          g += pixel.g * weight;
          b += pixel.b * weight;
        }
      }

      final rr = r.round().clamp(0, 255);
      final gg = g.round().clamp(0, 255);
      final bb = b.round().clamp(0, 255);

      image.setPixelRgb(x, y, rr, gg, bb);
    }
  }
}

void applyBinary(img.Image image, {int threshold = 128}) {
  final safeThreshold = threshold.clamp(0, 255);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final luma = img.getLuminance(pixel).round();

      if (luma >= safeThreshold) {
        image.setPixelRgb(x, y, 255, 255, 255);
      } else {
        image.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }
}