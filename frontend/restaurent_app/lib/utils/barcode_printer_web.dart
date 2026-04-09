import 'dart:html' as html;

void printBarcodeDirectly({
  required String itemName,
  required String quantity,
  required String unit,
  required String barcodeData,
  required String svg, // added
}) {
  final htmlContent = '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>Print Barcode</title>
    <style>
      body { margin: 0; padding: 0; text-align: center; font-family: Arial, sans-serif; }
      .label { font-size: 18px; font-weight: bold; margin-top: 40px; }
      .barcode { margin-top: 20px; }
    </style>
  </head>
  <body onload="window.print(); window.close();">
    <div class="label">
      <h5>$itemName &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; $quantity $unit</h5>
    </div>
    <div class="barcode">
      <div style="width:150px; margin:auto;">$svg</div>
    </div>
  </body>
</html>
''';

  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final iframe = html.IFrameElement()
    ..style.display = 'none'
    ..src = url;

  html.document.body!.append(iframe);

  iframe.onLoad.listen((event) {
    (iframe.contentWindow as html.Window?)?.print();
    html.Url.revokeObjectUrl(url);
    iframe.remove();
  });
}
