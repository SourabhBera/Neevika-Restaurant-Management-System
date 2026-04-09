// download_helper_io.dart
import 'dart:io';
import 'dart:typed_data';

/// Save bytes to the given targetPath. Returns the saved path.
Future<String> saveFile(Uint8List bytes, String targetPath, String mime) async {
  final file = File(targetPath);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
  return file.path;
}
