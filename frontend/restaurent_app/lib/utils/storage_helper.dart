import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Storage helper for saving files to Downloads folder (Play Store compliant)
/// 
/// Handles Android 10+ scoped storage without MANAGE_EXTERNAL_STORAGE
/// Files are saved to user-accessible Downloads folder
class StorageHelper {
  /// Save file to Downloads folder
  /// 
  /// Parameters:
  ///   - bytes: File content as Uint8List
  ///   - fileName: Desired filename (e.g., 'Report.xlsx')
  ///   - onSuccess: Callback with file path on success
  ///   - onError: Callback with error message on failure
  /// 
  /// Returns: File path if successful, null otherwise
  static Future<String?> saveToDownloads({
    required Uint8List bytes,
    required String fileName,
    BuildContext? context,
  }) async {
    try {
      // Get the main Downloads directory (not app-specific)
      // On Android, we extract the public Downloads folder from external storage
      Directory? downloadsDir;

      try {
        // Try to get the public Downloads folder on Android
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null && Platform.isAndroid) {
          // Strip app-specific path (e.g., /Android/data/com.tobasu.Neevika/files)
          // and navigate to public Downloads folder
          String publicPath = externalDir.path
              .replaceAll(RegExp(r'/Android/data/[^/]+/files.*'), '');
          downloadsDir = Directory('$publicPath/Download');
          
          // Ensure directory exists
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
        } else {
          // Fallback for non-Android platforms
          downloadsDir = await getDownloadsDirectory();
        }
      } catch (e) {
        debugPrint('Failed to get Downloads directory: $e');
        // Fallback to app documents directory
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        throw Exception('Could not access Downloads directory');
      }

      // Create unique filename if it already exists
      String filePath = '${downloadsDir.path}${Platform.pathSeparator}$fileName';
      File file = File(filePath);

      if (await file.exists()) {
        filePath = _getUniqueFilePath(filePath);
        file = File(filePath);
      }

      // Write file
      await file.writeAsBytes(bytes);

      debugPrint('File saved to: $filePath');
      return filePath;
    } catch (e, st) {
      debugPrint('Storage error: $e\n$st');
      return null;
    }
  }

  /// Generate unique filepath if file already exists
  /// Appends (1), (2), etc. to filename
  static String _getUniqueFilePath(String originalPath) {
    final file = File(originalPath);
    if (!file.existsSync()) return originalPath;

    final lastDot = originalPath.lastIndexOf('.');
    final basePath =
        lastDot > 0 ? originalPath.substring(0, lastDot) : originalPath;
    final extension = lastDot > 0 ? originalPath.substring(lastDot) : '';

    int counter = 1;
    String newPath;
    do {
      newPath = '$basePath($counter)$extension';
      counter++;
    } while (File(newPath).existsSync());

    return newPath;
  }

  /// Check if we have permission to write
  /// For Android 10+ with scoped storage, no permission check is needed
  /// (unless accessing other app's files)
  static Future<bool> hasStoragePermission() async {
    // For Android 10+, getDownloadsDirectory() doesn't require explicit permission
    // This is scoped storage - only the Downloads folder is accessible
    return true;
  }

  /// Get MIME type from file extension
  static String getMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'xlsx':
      case 'xls':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'csv':
        return 'text/csv';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }
}
