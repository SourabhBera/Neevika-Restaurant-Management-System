// lib/print_test_page.dart
// pubspec.yaml must include:
// flutter_pos_printer_platform_image_3
// esc_pos_utils
// permission_handler
// another_flushbar
// intl

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'usb_printer.dart'; // native MethodChannel wrapper

void showTopNotification(BuildContext context, String title, String body) {
  Flushbar(
    title: title,
    message: body,
    duration: const Duration(seconds: 3),
    flushbarPosition: FlushbarPosition.TOP,
    backgroundColor: Colors.green,
    margin: const EdgeInsets.all(8),
    borderRadius: BorderRadius.circular(8),
    icon: const Icon(Icons.notifications, color: Colors.white),
  ).show(context);
}

class PrintTestPage extends StatefulWidget {
  const PrintTestPage({super.key});

  @override
  _PrintTestPageState createState() => _PrintTestPageState();
}

class _PrintTestPageState extends State<PrintTestPage> {
  final PrinterManager printerManager = PrinterManager.instance;
  List<PrinterDevice> availablePrinters = [];
  PrinterDevice? selectedPrinter;
  bool isScanning = false;
  bool isPrinting = false;
  List<String> debugLogs = [];
  final ScrollController _scrollController = ScrollController();

  void _addDebugLog(String message) {
    final ts = DateFormat('HH:mm:ss').format(DateTime.now());
    final entry = '$ts: $message';
    setState(() => debugLogs.add(entry));
    // also print to console for adb
    print(entry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearDebugLogs() => setState(() => debugLogs.clear());

  @override
  void initState() {
    super.initState();
    _addDebugLog('App started — scanning for printers...');
    _scanForPrinters();
  }

  Future<void> _scanForPrinters() async {
    try {
      setState(() => isScanning = true);
      _addDebugLog('Starting discovery (USB)...');

      await [Permission.storage, Permission.photos].request();
      _addDebugLog('Requested permissions');

      availablePrinters.clear();
      selectedPrinter = null;

      Stream<PrinterDevice> stream = printerManager.discovery(type: PrinterType.usb);
      final sub = stream.listen((printer) {
        _addDebugLog('Found: ${printer.name} | VID:${printer.vendorId} PID:${printer.productId}');
        availablePrinters.add(printer);
        setState(() {});
      }, onError: (e) {
        _addDebugLog('Discovery error: $e');
      });

      await Future.delayed(const Duration(seconds: 2));
      await sub.cancel();

      if (availablePrinters.isEmpty) {
        _addDebugLog('No USB printers found');
        showTopNotification(context, 'Scan', 'No USB printers found');
      } else {
        _addDebugLog('Found ${availablePrinters.length} printer(s)');
      }
    } catch (e) {
      _addDebugLog('Scan exception: $e');
    } finally {
      setState(() => isScanning = false);
    }
  }

  String? _formatIdForConnect(dynamic id) {
    if (id == null) return null;
    try {
      return id.toString();
    } catch (e) {
      return null;
    }
  }

  int _intFromDynamic(dynamic v) {
    if (v == null) throw Exception('Null id');
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? int.parse(v);
    if (v is num) return v.toInt();
    throw Exception('Unsupported id type ${v.runtimeType}');
  }

  // --- Helper: send via native (all-in-one) ---
  Future<void> _nativeSendBytes(Uint8List bytes, {int timeoutMillis = 2000}) async {
    if (selectedPrinter == null) {
      _addDebugLog('❌ No printer selected (nativeSendBytes)');
      return;
    }
    setState(() => isPrinting = true);
    try {
      final vendor = _intFromDynamic(selectedPrinter!.vendorId);
      final product = _intFromDynamic(selectedPrinter!.productId);
      _addDebugLog('Native send: VID=$vendor PID=$product len=${bytes.length}');

      final res = await UsbPrinter.printRawBytes(
        vendorId: vendor,
        productId: product,
        bytes: bytes,
        timeoutMillis: timeoutMillis,
      );
      _addDebugLog('Native send result: $res');
    } catch (e, st) {
      _addDebugLog('Native send error: $e');
      _addDebugLog('STACK: $st');
    } finally {
      setState(() => isPrinting = false);
    }
  }

  // --- Print functions (all call native) ---

  Future<void> _printRawMinimalNative() async {
    final payload = <int>[];
    payload.addAll([0x1B, 0x40]); // ESC @
    payload.addAll(latin1.encode('HELLO FROM NATIVE\nFlutter Print Test\n'));
    payload.addAll(List.filled(12, 0x0A));
    await _nativeSendBytes(Uint8List.fromList(payload));
  }

  Future<void> _printEverycomNative() async {
    final bytes = <int>[];
    bytes.addAll([0x1B, 0x40]); // init
    bytes.addAll([0x1B, 0x52, 0x00]); // ESC R 0
    bytes.addAll(latin1.encode('EVERYCOM TEST\nEC901 Printer\n'));
    bytes.addAll(latin1.encode('Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}\n'));
    bytes.addAll(List.filled(10, 0x0A));
    bytes.addAll([0x1D, 0x56, 0x00]); // cut
    await _nativeSendBytes(Uint8List.fromList(bytes));
  }

  Future<void> _printGeneratorNative() async {
    // uses esc_pos_utils to build bytes but still send via native
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);

    List<int> bytes = [];
    bytes += gen.setStyles(PosStyles(align: PosAlign.center, bold: true));
    bytes += gen.text('HELLO WORLD');
    bytes += gen.text('Flutter Native Print');
    bytes += gen.setStyles(PosStyles(align: PosAlign.left));
    bytes += gen.text('Time: ${DateFormat('HH:mm:ss').format(DateTime.now())}');
    bytes += gen.feed(4);
    bytes += gen.cut();

    await _nativeSendBytes(Uint8List.fromList(bytes));
  }

  Future<void> _aggressiveBurstNative() async {
    final header = latin1.encode('AGGRESSIVE BURST\n');
    final body = latin1.encode('HELLO\nFrom Flutter\nTime: ${DateFormat('HH:mm:ss').format(DateTime.now())}\n');
    final feeds = List<int>.filled(40, 0x0A);
    final payload = Uint8List.fromList([0x1B, 0x40] + header + body + feeds);

    // We can either send whole payload to native (native will chunk), or repeat multiple sends:
    // here, send whole payload repeatedly (native already chunks using endpoint maxPacketSize)
    const int repeats = 4;
    for (int i = 0; i < repeats; i++) {
      _addDebugLog('Aggressive native repeat ${i + 1}/$repeats');
      await _nativeSendBytes(payload, timeoutMillis: 3000);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    // optional final cut
    await _nativeSendBytes(Uint8List.fromList([0x1D, 0x56, 0x00]));
  }

  // Test connection using native init (no heavy data)
  Future<void> _testConnectionNative() async {
    final init = Uint8List.fromList([0x1B, 0x40]); // ESC @
    await _nativeSendBytes(init);
  }

  // Fallback: try plugin send first, then native if user requests
  // (kept for debugging or comparison)
  Future<void> _sendViaPluginThenNativeFallback() async {
    if (selectedPrinter == null) {
      _addDebugLog('❌ No printer selected (plugin fallback)');
      return;
    }
    setState(() => isPrinting = true);
    try {
      _addDebugLog('Trying plugin send (for comparison)...');

      // Small test payload
      final payload = <int>[];
      payload.addAll([0x1B, 0x40]);
      payload.addAll(latin1.encode('PLUGIN ATTEMPT\nFrom Flutter\n'));
      payload.addAll(List.filled(10, 0x0A));
      final bytes = Uint8List.fromList(payload);

      // Use the plugin connect + send (for comparison only)
      final vid = _formatIdForConnect(selectedPrinter!.vendorId);
      final pid = _formatIdForConnect(selectedPrinter!.productId);

      try {
        await printerManager.connect(
          type: PrinterType.usb,
          model: UsbPrinterInput(name: selectedPrinter!.name ?? '', vendorId: vid, productId: pid),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await printerManager.send(type: PrinterType.usb, bytes: bytes);
        _addDebugLog('Plugin send reported success (but may not print physically).');
        await Future.delayed(const Duration(seconds: 2));
        await printerManager.disconnect(type: PrinterType.usb);
      } catch (e) {
        _addDebugLog('Plugin send failed: $e');
      }

      // Ask user if they want native fallback
      final doFallback = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Fallback to native?'),
          content: const Text('Plugin attempted to print. If nothing printed, fallback to native bulkTransfer?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes (native)')),
          ],
        ),
      );

      if (doFallback == true) {
        _addDebugLog('User chose native fallback — sending via native now');
        await _nativeSendBytes(bytes);
      } else {
        _addDebugLog('User cancelled native fallback');
      }
    } catch (e, st) {
      _addDebugLog('Plugin -> native fallback error: $e');
      _addDebugLog('STACK: $st');
    } finally {
      setState(() => isPrinting = false);
    }
  }



  // keep permission checker
  Future<void> _checkUSBPermissions() async {
    try {
      _addDebugLog('🔐 Checking storage permission status');
      final status = await Permission.storage.status;
      _addDebugLog('Storage permission: $status');
      if (!status.isGranted) {
        final res = await Permission.storage.request();
        _addDebugLog('Requested storage permission result: $res');
      }
      _addDebugLog('Approve any system USB permission popups when they appear.');
    } catch (e) {
      _addDebugLog('Permission check error: $e');
    }
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Everycom EC901 — Native Printing (fixed)'),
        actions: [
          IconButton(icon: const Icon(Icons.clear), onPressed: _clearDebugLogs),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: isScanning ? null : _scanForPrinters,
                  child: const Text('🔍 Scan for USB Printers'),
                ),
                const SizedBox(height: 8),
                if (isScanning)
                  const CircularProgressIndicator()
                else if (availablePrinters.isEmpty)
                  const Text('No USB printers found')
                else
                  SizedBox(
                    height: 140,
                    child: ListView.builder(
                      itemCount: availablePrinters.length,
                      itemBuilder: (context, idx) {
                        final p = availablePrinters[idx];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.print, size: 16),
                          title: Text(p.name ?? 'Unknown', style: const TextStyle(fontSize: 13)),
                          subtitle: Text('VID:${p.vendorId} PID:${p.productId}', style: const TextStyle(fontSize: 11)),
                          selected: selectedPrinter == p,
                          selectedTileColor: Colors.green.shade100,
                          onTap: () {
                            setState(() => selectedPrinter = p);
                            _addDebugLog('Selected: ${p.name} VID:${p.vendorId} PID:${p.productId} (types: ${p.vendorId.runtimeType}, ${p.productId.runtimeType})');
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                if (selectedPrinter != null)
                  Text('Selected: ${selectedPrinter!.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (isPrinting) const CircularProgressIndicator(),
                if (!isPrinting)
                  Wrap(
                    spacing: 8,
                    children: [
                      ElevatedButton(onPressed: _checkUSBPermissions, child: const Text('🔐 Check Permissions')),
                      ElevatedButton(onPressed: selectedPrinter == null ? null : _testConnectionNative, child: const Text('🔗 Test Connection (native)')),
                      ElevatedButton(onPressed: selectedPrinter == null ? null : _printRawMinimalNative, child: const Text('⚡ Raw Minimal (native)')),
                      ElevatedButton(onPressed: selectedPrinter == null ? null : _printEverycomNative, child: const Text('🖨 Everycom (native)')),
                      ElevatedButton(onPressed: selectedPrinter == null ? null : _printGeneratorNative, child: const Text('🖨 Generator (native)')),
                      ElevatedButton(onPressed: selectedPrinter == null ? null : _aggressiveBurstNative, child: const Text('🚀 Aggressive Burst (native)')),
                      ElevatedButton(onPressed: selectedPrinter == null ? null : _sendViaPluginThenNativeFallback, child: const Text('🔁 Plugin then Native (fallback)')),
                    ],
                  ),
                const SizedBox(height: 8),
                const Text('All print actions use native bulkTransfer now. Keep native Kotlin MainActivity in android/ folder.'),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black87,
              child: debugLogs.isEmpty
                  ? const Center(child: Text('No logs yet...', style: TextStyle(color: Colors.grey)))
                  : Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: debugLogs.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (context, i) {
                          final log = debugLogs[i];
                          Color col = Colors.white;
                          if (log.contains('❌')) col = Colors.red.shade300;
                          if (log.contains('sent') || log.contains('Native send result')) col = Colors.green.shade300;
                          if (log.contains('Aggressive')) col = Colors.orange.shade300;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: SelectableText(log, style: TextStyle(color: col, fontFamily: 'monospace')),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
