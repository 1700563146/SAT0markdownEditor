// ============================================================================
// 图片取色
//
// 从用户选定的图片中提取主要颜色，供「强调色」作为取色来源使用。
// ============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// 从图片中提取按重要性排序的主色列表。
class ImageAccent {
  ImageAccent._();

  static Future<List<Color>> fromImageFile(
    String imagePath, {
    int maxColors = 5,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const FileSystemException('图片文件不存在');
    }
    return fromBytes(await file.readAsBytes(), maxColors: maxColors);
  }

  static Future<List<Color>> fromBytes(
    Uint8List bytes, {
    int maxColors = 5,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw const FormatException('无法读取图片像素数据');
      }

      final rgba = byteData.buffer.asUint8List();
      final pixels = List<int>.filled(rgba.length ~/ 4, 0, growable: false);
      for (var i = 0; i < pixels.length; i++) {
        final o = i * 4;
        pixels[i] =
            (rgba[o + 3] << 24) | (rgba[o] << 16) | (rgba[o + 1] << 8) | rgba[o + 2];
      }

      final quantized = await QuantizerCelebi().quantize(pixels, maxColors);
      return Score.score(quantized.colorToCount, desired: maxColors)
          .map((argb) => Color(argb))
          .toList();
    } finally {
      image.dispose();
    }
  }
}
