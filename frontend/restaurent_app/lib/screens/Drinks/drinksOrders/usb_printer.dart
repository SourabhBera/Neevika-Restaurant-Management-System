// save as lib/usb_printer.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class UsbPrinter {
  static const MethodChannel _channel = MethodChannel('usb_printer_channel');

  /// vendorId and productId should be integers.
  /// bytes is Uint8List.
  static Future<String> printRawBytes({
    required int vendorId,
    required int productId,
    required Uint8List bytes,
    int timeoutMillis = 2000,
  }) async {
    final base64Str = base64Encode(bytes);
    final args = {
      'vendorId': vendorId,
      'productId': productId,
      'base64': base64Str,
      'timeout': timeoutMillis,
    };

    try {
      final res = await _channel.invokeMethod('printBytes', args);
      return res as String;
    } on PlatformException catch (e) {
      throw Exception('PlatformException: ${e.code} ${e.message} ${e.details}');
    } catch (e) {
      throw Exception('Unknown error: $e');
    }
  }
}
