// lib/utils/web_print.dart

@JS('window')
library print_window;

import 'package:js/js.dart';

@JS('open')
external dynamic openPrintWindow(String url, String name);