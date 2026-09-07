import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';

class EmergencyPhoto {
  const EmergencyPhoto({required this.bytes, required this.extension});
  static const maxBytes = 4 * 1024 * 1024;
  final Uint8List bytes;
  final String extension;

  static Future<EmergencyPhoto> fromFile(XFile file) async {
    if (await file.length() > maxBytes) {
      throw const FormatException(
        'Photo is too large. Choose an image up to 4 MB.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Choose an image up to 4 MB.');
    }
    final extension = imageExtension(bytes);
    if (extension == null) {
      throw const FormatException('Choose a JPEG, PNG, or WebP photo.');
    }
    // A matching extension/header alone does not prove the image can be opened.
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    } catch (_) {
      throw const FormatException(
        'This image could not be opened. Choose another photo.',
      );
    }
    return EmergencyPhoto(bytes: bytes, extension: extension);
  }

  static String? imageExtension(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'jpg';
    }
    if (bytes.length >= 8 &&
        base64Encode(bytes.sublist(0, 8)) == 'iVBORw0KGgo=') {
      return 'png';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'webp';
    }
    return null;
  }

  Map<String, String> toJson() => {
    'filename': 'emergency-photo.$extension',
    'content': base64Encode(bytes),
  };
}
