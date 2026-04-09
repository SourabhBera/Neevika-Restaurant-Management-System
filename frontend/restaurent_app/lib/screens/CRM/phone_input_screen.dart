import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:Neevika/screens/CRM/customer_form.dart';
import 'package:Neevika/screens/CRM/existing_user_details.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// ─── Breakpoint helper ────────────────────────────────────────────────────────
const double _kDesktopBreakpoint = 768.0;

class PhoneInputScreen extends StatefulWidget {
  final String? tableCode;
  const PhoneInputScreen({Key? key, this.tableCode}) : super(key: key);

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final phoneController = TextEditingController();
  bool _loading = false;
  List<dynamic> _allOffers = [];
  bool _offersLoaded = false;
  static final Map<String, List<dynamic>> _offerCache = {};

  // ─── Accent colour ────────────────────────────────────────────────────────
  static const Color _accent = Color(0xFFB07D2D);

  Future<void> _fetchOfferDetails() async {
    if (_offerCache.containsKey('all_offers')) {
      if (mounted) {
        setState(() => _allOffers = _offerCache['all_offers']!);
      }
      return;
    }

    final uri = Uri.parse('${dotenv.env['API_URL']}/crm/QR-offer/');

    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Failed to fetch offers');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is List && data.isNotEmpty) {
          data.sort((a, b) =>
              (b['offer_value'] as num).compareTo(a['offer_value'] as num));

          _offerCache['all_offers'] = data;

          if (mounted) {
            setState(() {
              _allOffers = data;
              _offersLoaded = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching offers: $e');
      if (mounted) {
        setState(() => _offersLoaded = true);
      }
    }
  }

  // ─── Step 1: Validate phone, send OTP, then open OTP sheet ───────────────
  Future<void> _submitPhone() async {
    final phone = phoneController.text.trim();

    if (phone.length != 10 || !RegExp(r'^\d{10}$').hasMatch(phone)) {
      _showError('Please enter a valid 10-digit phone number');
      return;
    }

    setState(() => _loading = true);

    try {
      // First check if the phone exists in CRM
      final crmResponse = await http.get(
        Uri.parse("${dotenv.env['API_URL']}/crm/QR/$phone"),
      ).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (crmResponse.statusCode == 200) {
        // Existing user — send OTP then open sheet
        setState(() => _loading = false);
        await _sendOtp(phone);
      } else if (crmResponse.statusCode == 404) {
        // New user — send OTP then open sheet for registration
        setState(() => _loading = false);
        await _sendOtp(phone);
      } else {
        setState(() => _loading = false);
        _showError('Error: ${crmResponse.statusCode}');
      }
    } on TimeoutException {
      setState(() => _loading = false);
      _showError('Request timeout. Please try again.');
    } catch (e) {
      setState(() => _loading = false);
      _showError('Error: $e');
    }
  }

  // ─── Step 2: Send OTP via backend ─────────────────────────────────────────
  Future<void> _sendOtp(String phone) async {
    setState(() => _loading = true);
    try {
      final url = Uri.parse("${dotenv.env['API_URL']}/auth/send-otp");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() => _loading = false);
        _openOtpSheet(phone);
      } else {
        setState(() => _loading = false);
        _showError(data["message"] ?? "Failed to send OTP");
      }
    } on TimeoutException {
      setState(() => _loading = false);
      _showError("OTP request timed out. Please try again.");
    } catch (e) {
      setState(() => _loading = false);
      _showError("Error sending OTP");
    }
  }

  // ─── Step 3: Open OTP sheet (bottom sheet on mobile, dialog on desktop) ──
  void _openOtpSheet(String phone) {
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
            child: CrmOtpSheet(
              phoneNumber: phone,
              onVerify: (otp) => _verifyOtpAndNavigate(phone, otp),
              onResend: () => _sendOtp(phone),
              isDialog: true,
              accent: _accent,
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
        builder: (_) => CrmOtpSheet(
          phoneNumber: phone,
          onVerify: (otp) => _verifyOtpAndNavigate(phone, otp),
          onResend: () => _sendOtp(phone),
          isDialog: false,
          accent: _accent,
        ),
      );
    }
  }

  // ─── Step 4: Verify OTP, then navigate to correct screen ─────────────────
  Future<void> _verifyOtpAndNavigate(String phone, String otp) async {
    if (otp.length != 6) {
      _showError("Enter a valid 6-digit OTP");
      return;
    }

    try {
      final url = Uri.parse("${dotenv.env['API_URL']}/auth/verify-otp");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone, "otp": otp}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (!mounted) return;

        // Close the OTP sheet/dialog
        Navigator.pop(context);

        // Now check CRM to decide where to navigate
        await _navigateAfterVerification(phone);
      } else {
        _showError(data["message"] ?? "OTP verification failed");
      }
    } on TimeoutException {
      _showError("Verification timed out. Please try again.");
    } catch (e) {
      _showError("Error verifying OTP");
    }
  }

  // ─── Step 5: Navigate based on CRM lookup ────────────────────────────────
  Future<void> _navigateAfterVerification(String phone) async {
    try {
      final response = await http.get(
        Uri.parse("${dotenv.env['API_URL']}/crm/QR/$phone"),
      ).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          data is Map &&
          data.containsKey('id') &&
          data['id'] != null) {
        // Existing user
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExistingUserDetailsScreen(customer: data),
          ),
        );
      } else {
        // New user — get best offer
        dynamic bestOffer;
        if (_allOffers.isNotEmpty) {
          bestOffer = _allOffers.first;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserDetailsPage(
              phone: phone,
              offerCode: bestOffer?['offer_code'] ?? "",
              offerId: bestOffer?['id'] ?? 0,
              offerType: bestOffer?['offer_type'] ?? "",
              offerValue: bestOffer?['offer_value']?.toString() ?? "0",
              allOffers: _allOffers,
              tableCode: widget.tableCode ?? "",
            ),
          ),
        );
      }
    } catch (e) {
      _showError("Error loading user details");
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchOfferDetails();
  }

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: DefaultTextStyle(
        style: GoogleFonts.poppins(color: Colors.black),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // ── Header banner ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFFB07D2D),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      "Special Gift Awaits:\nClaim Your Reward Now!",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 75,
                      height: 75,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'lib/assets/5k_logo.jpeg',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "5K FAMILY RESTAURANT",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.language, color: Colors.white),
                        SizedBox(width: 10),
                        Icon(Icons.phone, color: Colors.white),
                        SizedBox(width: 10),
                        Icon(Icons.camera_alt, color: Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                "Enter your details & claim it now!",
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              const SizedBox(height: 20),
              // ── Phone input ───────────────────────────────────────────────
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.poppins(),
                decoration: InputDecoration(
                  hintText: "Your Phone Number",
                  hintStyle: GoogleFonts.poppins(),
                  counterText: '',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFFB07D2D), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // ── Submit button ─────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _submitPhone,
                  icon: _loading
                      ? const SizedBox.shrink()
                      : const Icon(Icons.arrow_forward),
                  label: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          "Claim your reward",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── CRM OTP Sheet (mirrors LoginScreen's OtpBottomSheet) ────────────────────

class CrmOtpSheet extends StatefulWidget {
  final String phoneNumber;
  final Future<void> Function(String otp) onVerify;
  final VoidCallback onResend;
  final bool isDialog;
  final Color accent;

  const CrmOtpSheet({
    Key? key,
    required this.phoneNumber,
    required this.onVerify,
    required this.onResend,
    this.isDialog = false,
    required this.accent,
  }) : super(key: key);

  @override
  State<CrmOtpSheet> createState() => _CrmOtpSheetState();
}

class _CrmOtpSheetState extends State<CrmOtpSheet> {
  final List<TextEditingController> _otpDigits =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus =
      List.generate(6, (_) => FocusNode());

  bool _isVerifying = false;
  int _resendTimer = 30;
  Timer? _timer;

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

  Future<void> _handleVerify() async {
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
    if (mounted) _otpFocus[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDialog) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: _buildContent(),
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.58,
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

  Widget _buildContent() {
    final accent = widget.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.lock_outline_rounded, size: 36, color: accent),
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
          'We sent a 6-digit code to',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 2),
        Text(
          widget.phoneNumber,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
        const SizedBox(height: 24),
        // OTP boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (i) => _buildOtpBox(i, accent)),
        ),
        const SizedBox(height: 24),
        // Verify button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isVerifying ? null : _handleVerify,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              backgroundColor: accent,
              disabledBackgroundColor: accent.withOpacity(0.6),
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
        // Resend row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Didn't receive code? ",
              style:
                  GoogleFonts.poppins(color: Colors.grey[600], fontSize: 13),
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
                  color: _resendTimer > 0 ? Colors.grey[400] : accent,
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

  Widget _buildOtpBox(int index, Color accent) {
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
            borderSide: BorderSide(color: accent, width: 2),
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