// utils/url_strategy_web.dart
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

Future<void> importAndSetUrlStrategy() async {
  setUrlStrategy(PathUrlStrategy());
}
