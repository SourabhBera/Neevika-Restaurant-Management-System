import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Future<void> Function() onInitializationComplete;

  const SplashScreen({super.key, required this.onInitializationComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(seconds: 2)); // Simulate splash delay
    await widget.onInitializationComplete(); // Will handle routing from main
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'lib/assets/Neevika_logo.jpg',
          width: 200, // adjust size as needed
        ),
      ),
    );
  }
}
