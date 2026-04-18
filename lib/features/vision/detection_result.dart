import 'package:flutter/material.dart';

class DetectionResult {
  final Rect box; // normalized: 0.0 - 1.0
  final String label;
  final double score;

  const DetectionResult({
    required this.box,
    required this.label,
    required this.score,
  });
}