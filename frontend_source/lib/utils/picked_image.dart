import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

/// A picked photo held in memory, so the same code works on Android, iOS and
/// the web (dart:io's File does not exist in a browser).
class PickedImage {
  final Uint8List bytes;
  final String name;
  final String mimeType;

  PickedImage._(this.bytes, this.name, this.mimeType);

  static Future<PickedImage> fromXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final ext = _extensionOf(file.name);
    return PickedImage._(bytes, file.name, file.mimeType ?? _mimeFromExtension(ext));
  }

  String get extension => _extensionOf(name);

  static String _extensionOf(String name) =>
      name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';

  static String _mimeFromExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
