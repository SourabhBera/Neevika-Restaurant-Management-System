// // lib/util/print_service_web.dart
import 'dart:js_util' as js_util;
import 'package:js/js.dart';

@JS('window')
external dynamic get window;

void triggerPrintWindow(String htmlContent) {
  final popup = js_util.callMethod(
    window,
    'open',
    ['', 'Print', 'width=800,height=600'],
  );

  if (popup != null) {
    final doc = js_util.getProperty(popup, 'document');
    js_util.callMethod(doc, 'open', []);
    js_util.callMethod(
      doc,
      'write',
      ['''
        <html>
          <head>
            <title>Print</title>
            <style>
              @media print {
                body { font-family: Arial, sans-serif; font-size: 24px; margin: 0; padding: 0; }
                table { width: 100%; border-collapse: collapse; margin: 0; padding: 0; }
                td, th { padding: 4px; }
              }
            </style>
          </head>
          <body onload="window.print(); window.close();">
            $htmlContent
          </body>
        </html>
      '''],
    );
    js_util.callMethod(doc, 'close', []);
  } else {
    print("Popup blocked or failed to open.");
  }
}

