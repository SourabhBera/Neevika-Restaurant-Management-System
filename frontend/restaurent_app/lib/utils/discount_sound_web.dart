// lib/utils/discount_sound_web.dart
// Only compile this on web

// This file will only be imported on web
// so it's safe to use dart:html and dart:js_util here

// Only compiled on web
import 'dart:html' as html;
import 'dart:js_util' as js_util;

void triggerCelebrationWeb() {
  try {
    // Vibrate
    js_util.callMethod(html.window.navigator, 'vibrate', [500]);

    // Play sound
    final audio = html.AudioElement('assets/sounds/notification.mp3')
      ..autoplay = true
      ..play();
  } catch (e) {
    print('Web celebration error: $e');
  }
}
