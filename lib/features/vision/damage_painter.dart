import 'package:flutter/material.dart';

import 'detection_result.dart';

class DamagePainter extends CustomPainter {
  final List<DetectionResult> results;

  const DamagePainter({
    required this.results,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.75)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Crosshair tengah
    canvas.drawLine(
      Offset(size.width / 2 - 20, size.height / 2),
      Offset(size.width / 2 + 20, size.height / 2),
      guidePaint,
    );

    canvas.drawLine(
      Offset(size.width / 2, size.height / 2 - 20),
      Offset(size.width / 2, size.height / 2 + 20),
      guidePaint,
    );

    // Kalau belum ada hasil deteksi, tampilkan label standby
    if (results.isEmpty) {
      const textSpan = TextSpan(
        text: ' Searching for Road Damage... ',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.redAccent,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2, size.height * 0.18),
      );
      return;
    }

    for (final res in results) {
      // Normalized -> logical pixel
      final double finalX = res.box.left * size.width;
      final double finalY = res.box.top * size.height;
      final double finalW = res.box.width * size.width;
      final double finalH = res.box.height * size.height;

      final rect = Rect.fromLTWH(finalX, finalY, finalW, finalH);

      final bool isPothole = res.label.contains('D40');
      final bool isLongCrack = res.label.contains('D00');

      final Color primaryColor = isPothole
          ? Colors.redAccent
          : isLongCrack
              ? Colors.yellow.shade700
              : Colors.orange;

      final boxPaint = Paint()
        ..color = primaryColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      canvas.drawRect(rect, boxPaint);

      final String labelText =
          ' ${res.label} - ${(res.score * 100).toStringAsFixed(0)}% ';

      final shadowTextPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: Colors.black.withOpacity(0.65),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelTextPainter = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            backgroundColor: primaryColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      double textX = finalX;
      double textY = finalY - 26;

      if (textY < 0) {
        textY = finalY + finalH + 6;
      }

      // Shadow
      shadowTextPainter.paint(canvas, Offset(textX + 1.5, textY + 1.5));

      // Main label
      labelTextPainter.paint(canvas, Offset(textX, textY));
    }
  }

  @override
  bool shouldRepaint(covariant DamagePainter oldDelegate) {
    return oldDelegate.results != results;
  }
}