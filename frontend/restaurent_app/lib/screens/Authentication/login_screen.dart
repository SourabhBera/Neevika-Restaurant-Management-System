import 'package:Neevika/screens/Authentication/forgetPassword_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:Neevika/screens/Authentication/register_screen.dart';
import 'package:Neevika/services/fcm_service.dart';
import 'package:Neevika/services/token_service.dart';
import 'package:Neevika/services/socket_service.dart';
import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ─── Breakpoint helper ────────────────────────────────────────────────────────
// A screen is "desktop" when its width exceeds this threshold.
const double _kDesktopBreakpoint = 768.0;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final emailOrPhoneController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool loginWithOtp = false;
  bool showPassword = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  // ─── Accent colour (single source of truth) ───────────────────────────────
  static const Color _accent = Color(0xFFD95326);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    emailOrPhoneController.dispose();
    passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ─── Auth helpers (unchanged) ─────────────────────────────────────────────

  bool isValidJWT(String token) {
    final jwtRegExp = RegExp(
      r'^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$',
    );
    return jwtRegExp.hasMatch(token);
  }

  Future<void> _initializeFCM(String token) async {
    try {
      final fcmService = FCMService();
      final decoded = JwtDecoder.decode(token);
      final userId = decoded['id'];
      await fcmService.initialize((fcmToken) async {
        try {
          if (fcmToken != null && userId != null) {
            final tokenService = TokenService();
            await tokenService.sendToken(fcmToken, userId);
          }
        } catch (e) {
          debugPrint('❌ Error sending FCM token: $e');
        }
      });
    } catch (e) {
      debugPrint('❌ FCM initialization failed: $e');
    }
  }

  Future<void> _sendOtp() async {
    final phone = emailOrPhoneController.text.trim();
    if (phone.length != 10) {
      showError("Enter a valid 10-digit mobile number");
      return;
    }
    setState(() => isLoading = true);
    try {
      final url = Uri.parse("${dotenv.env['API_URL']}/auth/send-otp");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() => isLoading = false);
        _openOtpSheet();
      } else {
        setState(() => isLoading = false);
        showError(data["message"] ?? "Failed to send OTP");
      }
    } catch (e) {
      setState(() => isLoading = false);
      showError("Error sending OTP");
    }
  }

  Future<void> _login() async {
    final emailOrPhone = emailOrPhoneController.text.trim();
    final password = passwordController.text;
    if (emailOrPhone.isEmpty || password.isEmpty) {
      showError('Email or phone and password are required');
      return;
    }
    setState(() => isLoading = true);
    try {
      final url = Uri.parse('${dotenv.env['API_URL']}/auth/login');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'emailOrPhone': emailOrPhone, 'password': password}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwtToken', token);
        // Connect socket for force-logout listening
        final decoded = JwtDecoder.decode(token);
        SocketService().connect(decoded['id']);
        _navigateUserAfterLogin(token);
        _initializeFCM(token);
      } else {
        final errorData = jsonDecode(response.body);
        showError(errorData['message'] ?? 'Login failed.');
      }
    } catch (e) {
      showError('Error: ${e.toString()}');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _navigateUserAfterLogin(String token) {
    final decodedToken = JwtDecoder.decode(token);
    final userRole = decodedToken['role'];
    if (userRole == 'Admin') {
      Navigator.pushNamedAndRemoveUntil(context, '/Dashboard', (_) => false);
    } else if (userRole == 'Captain' || userRole == 'Steward') {
      Navigator.pushNamedAndRemoveUntil(context, '/menu', (_) => false);
    } else if (userRole == 'Main Chef' || userRole == 'Assistant Chef') {
      Navigator.pushNamedAndRemoveUntil(context, '/orders', (_) => false);
    } else if (userRole == 'Bartender') {
      Navigator.pushNamedAndRemoveUntil(
          context, '/drink-orders', (_) => false);
    } else if (userRole == 'Billing Team') {
      Navigator.pushNamedAndRemoveUntil(context, '/tables', (_) => false);
    } else if (userRole == 'Store Keeper') {
      Navigator.pushNamedAndRemoveUntil(context, '/inventory', (_) => false);
    } else if (userRole == 'Accountant') {
      Navigator.pushNamedAndRemoveUntil(context, '/expense', (_) => false);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    }
  }

  void showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ─── OTP sheet / dialog ────────────────────────────────────────────────────

  /// On mobile → bottom sheet; on desktop → centered dialog.
  void _openOtpSheet() {
    if (!mounted) return;
    final isDesktop =
        MediaQuery.of(context).size.width >= _kDesktopBreakpoint;

    if (isDesktop) {
      showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.45),
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: OtpBottomSheet(
              phoneNumber: emailOrPhoneController.text.trim(),
              onVerify: _verifyOtpFromSheet,
              onResend: _sendOtp,
              isDialog: true,
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (_) => OtpBottomSheet(
          phoneNumber: emailOrPhoneController.text.trim(),
          onVerify: _verifyOtpFromSheet,
          onResend: _sendOtp,
          isDialog: false,
        ),
      );
    }
  }

  Future<void> _verifyOtpFromSheet(String otp) async {
    final phone = emailOrPhoneController.text.trim();
    if (otp.length != 6) {
      showError("Enter valid 6-digit OTP");
      return;
    }
    setState(() => isLoading = true);
    try {
      final url = Uri.parse("${dotenv.env['API_URL']}/auth/verify-otp");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone, "otp": otp}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final token = data['token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwtToken', token);
        // Connect socket for force-logout listening
        final decodedOtp = JwtDecoder.decode(token);
        SocketService().connect(decodedOtp['id']);
        if (mounted) {
          Navigator.pop(context);
          _navigateUserAfterLogin(token);
          _initializeFCM(token);
        }
      } else {
        showError(data["message"] ?? "OTP verification failed");
      }
    } catch (e) {
      showError("Error verifying OTP");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= _kDesktopBreakpoint;
          return isDesktop
              ? _buildDesktopLayout(constraints)
              : _buildMobileLayout();
        },
      ),
    );
  }

  // ─── Mobile layout (original, unchanged) ──────────────────────────────────

  Widget _buildMobileLayout() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.grey[50]!,
            Colors.white,
            _accent.withOpacity(0.02),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 440),
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: _cardDecoration(),
                    child: _buildFormContent(),
                  ),
                ),
                const SizedBox(height: 24),
                _buildFooterText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Desktop layout (two-panel) ────────────────────────────────────────────

  Widget _buildDesktopLayout(BoxConstraints constraints) {
    return Row(
      children: [
        // ── Left branding panel ────────────────────────────────────────────
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accent,
                  const Color(0xFFE85D2F),
                  _accent.withOpacity(0.85),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.restaurant_menu_rounded,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Neevika',
                    style: GoogleFonts.poppins(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Restaurant Management',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.8),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 56),
                  // Feature bullets
                  ..._desktopFeatures.map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 48, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(f.$2,
                                color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            f.$1,
                            style: GoogleFonts.poppins(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Right form panel ───────────────────────────────────────────────
        Expanded(
          flex: 6,
          child: Container(
            color: Colors.grey[50],
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 56, vertical: 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Small top branding (desktop only — keeps context)
                          Row(
                            children: [
                              Icon(
                                Icons.restaurant_menu_rounded,
                                color: _accent,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Neevika',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(36),
                            decoration: _cardDecoration(),
                            child: _buildFormContent(isDesktop: true),
                          ),
                          const SizedBox(height: 24),
                          _buildFooterText(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const List<(String, IconData)> _desktopFeatures = [
    ('Manage orders in real-time', Icons.receipt_long_rounded),
    ('Role-based staff access', Icons.group_rounded),
    ('Inventory & expense tracking', Icons.inventory_2_rounded),
    ('Smart billing & tables', Icons.table_restaurant_rounded),
  ];

  // ─── Shared form content ───────────────────────────────────────────────────

  Widget _buildFormContent({bool isDesktop = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome back',
          style: GoogleFonts.poppins(
            fontSize: isDesktop ? 26 : 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sign in to continue to your dashboard',
          style: GoogleFonts.poppins(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        // Mode chips + register
        Row(
          children: [
            _buildModeChip('Password', !loginWithOtp, 100),
            const SizedBox(width: 12),
            _buildModeChip('OTP', loginWithOtp, 60),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RegisterScreen(),
                ),
              ),
              child: Text(
                'Register',
                style: GoogleFonts.poppins(
                  color: _accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildInput(
          controller: emailOrPhoneController,
          hint: loginWithOtp
              ? '10-digit mobile number'
              : 'Email or phone number',
          prefix: Icons.person_outline_rounded,
          keyboardType: loginWithOtp
              ? TextInputType.phone
              : TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: loginWithOtp
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    _buildInput(
                      controller: passwordController,
                      hint: 'Password',
                      prefix: Icons.lock_outline_rounded,
                      obscure: true,
                      suffixIcon: IconButton(
                        splashRadius: 20,
                        onPressed: () =>
                            setState(() => showPassword = !showPassword),
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        // Primary button
        SizedBox(
          width: double.infinity,
          height: isDesktop ? 58 : 54,
          child: ElevatedButton(
            onPressed: isLoading ? null : (loginWithOtp ? _sendOtp : _login),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: EdgeInsets.zero,
              backgroundColor: _accent,
              disabledBackgroundColor: _accent.withOpacity(0.6),
            ),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLoading
                      ? [
                          _accent.withOpacity(0.6),
                          _accent.withOpacity(0.6),
                        ]
                      : [_accent, const Color(0xFFE85D2F)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                alignment: Alignment.center,
                child: isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        loginWithOtp ? 'Send OTP' : 'Sign In',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Divider
        Row(
          children: [
            Expanded(
                child: Divider(color: Colors.grey[300], thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('or',
                  style: GoogleFonts.poppins(
                      color: Colors.grey[500], fontSize: 13)),
            ),
            Expanded(
                child: Divider(color: Colors.grey[300], thickness: 1)),
          ],
        ),
        const SizedBox(height: 16),
        // Forgot / toggle OTP
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ForgotPasswordScreen()),
              ),
              child: Text(
                'Forgot password?',
                style: GoogleFonts.poppins(
                  color: _accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => loginWithOtp = !loginWithOtp),
              child: Text(
                loginWithOtp ? 'Use Password' : 'Use OTP',
                style: GoogleFonts.poppins(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Shared widgets ────────────────────────────────────────────────────────

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
        ],
      );

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accent.withOpacity(0.1),
                  _accent.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.restaurant_menu_rounded,
                size: 64, color: _accent),
          ),
          const SizedBox(height: 16),
          Text(
            'Neevika',
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Restaurant Management',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterText() {
    return Text(
      'Need help? Contact support@neevika.com',
      style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 12),
    );
  }

  Widget _buildModeChip(String label, bool active, double boxWidth) {
    return SizedBox(
      width: boxWidth,
      child: GestureDetector(
        onTap: () => setState(() => loginWithOtp = (label == 'OTP')),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    colors: [_accent, _accent.withOpacity(0.8)])
                : null,
            color: active ? null : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: _accent.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: active ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    IconData? prefix,
    Widget? suffixIcon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure && !showPassword,
        keyboardType: keyboardType,
        style: GoogleFonts.poppins(fontSize: 15),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.grey[50],
          hintText: hint,
          hintStyle:
              GoogleFonts.poppins(color: Colors.grey[400], fontSize: 14),
          prefixIcon: prefix != null
              ? Icon(prefix, color: Colors.grey[600], size: 22)
              : null,
          suffixIcon: suffixIcon,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _accent, width: 2),
          ),
        ),
      ),
    );
  }
}

// ─── OTP widget ───────────────────────────────────────────────────────────────

class OtpBottomSheet extends StatefulWidget {
  final String phoneNumber;
  final Function(String) onVerify;
  final VoidCallback onResend;
  final bool isDialog;

  const OtpBottomSheet({
    super.key,
    required this.phoneNumber,
    required this.onVerify,
    required this.onResend,
    this.isDialog = false,
  });

  @override
  State<OtpBottomSheet> createState() => _OtpBottomSheetState();
}

class _OtpBottomSheetState extends State<OtpBottomSheet> {
  final List<TextEditingController> _otpDigits =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus =
      List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  int _resendTimer = 30;
  Timer? _timer;

  static const Color _accent = Color(0xFFD95326);

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _otpFocus[0].requestFocus();
    });
  }

  void _startResendTimer() {
    _resendTimer = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_resendTimer > 0) {
            _resendTimer--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _otpDigits) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  void _handleVerify() async {
    final otp = _otpDigits.map((c) => c.text).join();
    if (otp.length == 6) {
      setState(() => _isVerifying = true);
      await widget.onVerify(otp);
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _handleResend() {
    widget.onResend();
    _startResendTimer();
    for (final c in _otpDigits) c.clear();
    _otpFocus[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // Dialog variant: plain container, no drag handle, no DraggableScrollableSheet
    if (widget.isDialog) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: _buildContent(),
        ),
      );
    }

    // Bottom-sheet variant (original)
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  // Shared OTP content (used in both sheet and dialog)
  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_outline_rounded,
              size: 36, color: _accent),
        ),
        const SizedBox(height: 16),
        Text(
          'Enter OTP',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'We have sent a 6-digit code to',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 2),
        Text(
          widget.phoneNumber,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _accent,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, _buildOtpBox),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isVerifying ? null : _handleVerify,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              backgroundColor: _accent,
              disabledBackgroundColor: _accent.withOpacity(0.6),
            ),
            child: _isVerifying
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    'Verify OTP',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Didn't receive code? ",
              style: GoogleFonts.poppins(
                  color: Colors.grey[600], fontSize: 13),
            ),
            TextButton(
              onPressed: _resendTimer == 0 ? _handleResend : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
              child: Text(
                _resendTimer > 0
                    ? 'Resend in ${_resendTimer}s'
                    : 'Resend OTP',
                style: GoogleFonts.poppins(
                  color:
                      _resendTimer > 0 ? Colors.grey[400] : _accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtpBox(int index) {
    return Container(
      width: 50,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _otpDigits[index],
        focusNode: _otpFocus[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        style: GoogleFonts.poppins(
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(14),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _accent, width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onChanged: (val) {
          if (val.isNotEmpty) {
            if (index + 1 != _otpDigits.length) {
              _otpFocus[index + 1].requestFocus();
            } else {
              _otpFocus[index].unfocus();
              _handleVerify();
            }
          } else {
            if (index > 0) _otpFocus[index - 1].requestFocus();
          }
        },
        onSubmitted: (_) {
          if (index == _otpDigits.length - 1) _handleVerify();
        },
      ),
    );
  }
}
