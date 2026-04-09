// download_helper_web.dart
// Note: this file will only be used when building for web (conditional import).
import 'dart:html' as html;
import 'dart:typed_data';

/// Trigger browser download. `targetPath` is used as the filename here.
/// Returns the filename (not a path).
Future<String> saveFile(Uint8List bytes, String filename, String mime) async {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.document.createElement('a') as html.AnchorElement;
  anchor.href = url;
  anchor.download = filename;
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return filename;
}
