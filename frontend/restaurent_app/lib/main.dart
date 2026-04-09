import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'firebase_options.dart';
import 'package:Neevika/widgets/splashScreen.dart';
import 'package:Neevika/routes/routes.dart';
import 'package:Neevika/services/auth_service.dart';
import 'package:Neevika/services/fcm_service.dart';
import 'package:Neevika/services/token_service.dart';
import 'package:Neevika/services/socket_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'utils/url_strategy_stub.dart'
    if (dart.library.html) 'utils/url_strategy_web.dart';

import 'package:flutter_screenutil/flutter_screenutil.dart'; // ✅ Add this

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();


Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await importAndSetUrlStrategy();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  tz.initializeTimeZones();
  await dotenv.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      // 📱 Base design size (iPhone 12 reference)
      designSize: const Size(390, 844),
      minTextAdapt: true, // ✅ Adapts text for small/large devices
      splitScreenMode: true, // ✅ Handles tablets/split screen
      builder: (_, child) {
        return MaterialApp(
          title: 'Neevika',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,

          // 🔥 THIS IS THE IMPORTANT LINE
          scaffoldMessengerKey: rootScaffoldMessengerKey,

          initialRoute: '/',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/':
                return MaterialPageRoute(
                  builder: (_) =>
                      SplashScreen(onInitializationComplete: _setupApp),
                );
              default:
                return AppRoutes.generateRoute(settings);
            }
          },
        );

      },
    );
  }
}

Future<void> _setupApp() async {
  final AuthService authService = AuthService();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('jwtToken');
  final currentPath = Uri.base.path;

  try {
    final isLoggedIn = await authService.isLoggedIn();

    if (!isLoggedIn || token == null) {
      if (currentPath == '/customer-form' ||
          currentPath.startsWith('/customerQr/')) {
        return; // Public route
      } else {
        navigatorKey.currentState?.pushReplacementNamed('/login');
        return;
      }
    }

    final decodedToken = JwtDecoder.decode(token);
    final userRole = decodedToken['role'];

    // Connect socket for force-logout listening on existing session
    final userId = decodedToken['id'];
    if (userId != null) {
      SocketService().connect(userId);
    }

    if (currentPath == '/' || currentPath == '/login') {
      if (userRole == 'Admin') {
        navigatorKey.currentState?.pushReplacementNamed('/Dashboard');
      } else {
        navigatorKey.currentState?.pushReplacementNamed('/home');
      }
    }
  } catch (e) {
    print('Error during setup: $e');
    navigatorKey.currentState?.pushReplacementNamed('/login');
  }
}
