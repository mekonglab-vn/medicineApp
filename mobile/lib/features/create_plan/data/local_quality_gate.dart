import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class LocalQualityResult {
  const LocalQualityResult({
    required this.state,
    this.rejectReason,
    required this.guidance,
    required this.metrics,
  });

  final String state;
  final String? rejectReason;
  final String guidance;
  final Map<String, num> metrics;
}

Future<LocalQualityResult> assessLocalImageQuality(Uint8List bytes) async {
  final raw = await compute(_assessLocalImageQuality, bytes);
  return LocalQualityResult(
    state: raw['state'] as String,
    rejectReason: raw['rejectReason'] as String?,
    guidance: raw['guidance'] as String,
    metrics: (raw['metrics'] as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key as String, value as num),
    ),
  );
}

Map<String, Object?> _assessLocalImageQuality(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return {
      'state': 'REJECT',
      'rejectReason': 'INVALID_IMAGE',
      'guidance': 'Không đọc được ảnh. Hãy chọn ảnh khác.',
      'metrics': <String, num>{},
    };
  }

  final scaled = decoded.width > 512
      ? img.copyResize(decoded, width: 512)
      : decoded;
  final width = scaled.width;
  final height = scaled.height;

  var brightPixels = 0;
  var edgeSum = 0.0;
  var minX = width;
  var minY = height;
  var maxX = 0;
  var maxY = 0;

  final luminance = List<List<double>>.generate(
    height,
    (_) => List<double>.filled(width, 0),
  );

  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final pixel = scaled.getPixel(x, y);
      final value = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      luminance[y][x] = value;

      if (value >= 245) {
        brightPixels += 1;
      }

      if (value <= 215) {
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }

      if (x > 0) {
        edgeSum += (value - luminance[y][x - 1]).abs();
      }
      if (y > 0) {
        edgeSum += (value - luminance[y - 1][x]).abs();
      }
    }
  }

  final totalPixels = width * height;
  final glareRatio = brightPixels / totalPixels;
  final edgeScore = edgeSum / totalPixels;
  final margin = (math.min(width, height) * 0.02).round();
  final cutoff =
      minX <= margin ||
      minY <= margin ||
      maxX >= (width - margin) ||
      maxY >= (height - margin);

  final metrics = <String, num>{
    'edgeScore': double.parse(edgeScore.toStringAsFixed(2)),
    'glareRatio': double.parse(glareRatio.toStringAsFixed(4)),
    'width': decoded.width,
    'height': decoded.height,
  };

  if (edgeScore < 10) {
    return {
      'state': 'REJECT',
      'rejectReason': 'BLURRY_IMAGE',
      'guidance': 'Ảnh mờ quá. Cố gắng giữ chắc tay nhé.',
      'metrics': metrics,
    };
  }

  if (glareRatio > 0.2) {
    return {
      'state': 'REJECT',
      'rejectReason': 'GLARE_IMAGE',
      'guidance': 'Ảnh bị chói sáng. Đổi góc một chút cho rõ chữ.',
      'metrics': metrics,
    };
  }

  // Chấp nhận bị cắt góc nếu vùng ảnh bên trong nét căng (>14 edgeScore).
  // Chỉ cảnh báo nếu ảnh chỉ tàm tạm nét.
  if (cutoff && edgeScore < 14) {
    return {
      'state': 'WARNING',
      'rejectReason': 'CONTENT_CUTOFF',
      'guidance': 'Có vẻ ảnh bị cắt mất chữ. Thử lùi ra xa một chút.',
      'metrics': metrics,
    };
  }

  if (edgeScore < 16 ||
      glareRatio > 0.1 ||
      decoded.width < 1000 ||
      decoded.height < 1000) {
    return {
      'state': 'WARNING',
      'rejectReason': null,
      'guidance': 'Chữ hơi mờ, kết quả quét có thể không chính xác 100%.',
      'metrics': metrics,
    };
  }

  return {
    'state': 'GOOD',
    'rejectReason': null,
    'guidance': 'Ảnh rất nét! Đang gửi đi xử lý...',
    'metrics': metrics,
  };
}
