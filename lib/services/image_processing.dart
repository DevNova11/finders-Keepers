import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ProcessedImage {
  final Uint8List jpeg;
  final String dHash;
  const ProcessedImage(this.jpeg, this.dHash);
}

/// Image pipeline run off the UI isolate before anything is uploaded:
///  * downscale to max 1280 px (saves campus mobile data, faster retries)
///  * re-encode to JPEG, which drops EXIF metadata — including GPS
///    coordinates and device identifiers embedded by the camera
///  * optional heavy blur for sensitive items (ID cards, phones, wallets)
///  * 64-bit difference hash (dHash) for image-similarity matching
class ImageProcessing {
  ImageProcessing._();

  static Future<ProcessedImage> process(File file, {bool blur = false}) async {
    final bytes = await file.readAsBytes();
    return Isolate.run(() => processBytes(bytes, blur: blur));
  }

  static ProcessedImage processBytes(Uint8List bytes, {bool blur = false}) {
    var image = img.decodeImage(bytes);
    if (image == null) throw const FormatException('Unsupported image');
    image = img.bakeOrientation(image);
    if (image.width > 1280 || image.height > 1280) {
      image = image.width >= image.height
          ? img.copyResize(image, width: 1280)
          : img.copyResize(image, height: 1280);
    }
    // Hash is computed on the un-blurred image so blurred public photos
    // still match the owner's photo of the same object.
    final hash = dHash(image);
    if (blur) image = img.gaussianBlur(image, radius: 18);
    image.exif = img.ExifData(); // belt and braces: no metadata survives
    return ProcessedImage(img.encodeJpg(image, quality: 80), hash);
  }

  /// Difference hash: shrink to 9x8 grayscale, compare adjacent pixels.
  static String dHash(img.Image image) {
    final small = img.grayscale(
      img.copyResize(
        image,
        width: 9,
        height: 8,
        interpolation: img.Interpolation.average,
      ),
    );
    var bits = BigInt.zero;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = small.getPixel(x, y).luminance;
        final right = small.getPixel(x + 1, y).luminance;
        bits = (bits << 1) | (left > right ? BigInt.one : BigInt.zero);
      }
    }
    return bits.toRadixString(16).padLeft(16, '0');
  }

  /// Similarity in 0..1 from the Hamming distance of two dHashes.
  static double similarity(String a, String b) {
    if (a.length != 16 || b.length != 16) return 0;
    var x = BigInt.parse(a, radix: 16) ^ BigInt.parse(b, radix: 16);
    var distance = 0;
    while (x > BigInt.zero) {
      if (x & BigInt.one == BigInt.one) distance++;
      x >>= 1;
    }
    return 1 - distance / 64;
  }
}
