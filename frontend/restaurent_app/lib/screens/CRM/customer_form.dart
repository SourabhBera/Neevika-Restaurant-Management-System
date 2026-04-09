// ============================================================
// UserDetailsPage - Enhanced Lottery Screen
// Improvements:
//  • Multi-phase spin: fast → decelerate → precise land
//  • Shimmer header title on spin dialog
//  • Animated gradient background in discount screen
//  • Particle-rain confetti (more particles, longer trail)
//  • Pulsing glow on winner window
//  • Spring-bounce reveal on discount card
//  • Staggered bulb columns with sin-wave phasing
// ============================================================

import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:Neevika/utils/discount_sound_stub.dart'
    if (dart.library.html) 'package:Neevika/utils/discount_sound_web.dart'
    as discount_sound_web;

// ── Date input formatter ─────────────────────────────────────
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll('-', '');
    if (text.length > 8) text = text.substring(0, 8);
    String newText = '';
    for (int i = 0; i < text.length; i++) {
      newText += text[i];
      if ((i == 1 || i == 3) && i != text.length - 1) newText += '-';
    }
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

// ── Constants ────────────────────────────────────────────────
const _kGold = Color(0xFFFFD700);
const _kGold2 = Color(0xFFFFA500);
const _kDeepRed = Color(0xFF300000);
const _kDarkRed = Color(0xFF4a0000);
const _kRed = Color(0xFFB22222);
const _kGreen = Color(0xFF00A884);
const _kGreenDark = Color(0xFF007B67);

// ── Widget ───────────────────────────────────────────────────
class UserDetailsPage extends StatefulWidget {
  final String phone;
  final String? offerCode;
  final int? offerId;
  final String? offerType;
  final String? offerValue;
  final String? tableCode;
  final List<dynamic> allOffers;

  const UserDetailsPage({
    Key? key,
    required this.phone,
    this.offerCode,
    this.offerId,
    this.offerType,
    this.offerValue,
    this.tableCode,
    this.allOffers = const [],
  }) : super(key: key);

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController birthdayController = TextEditingController();
  final TextEditingController anniversaryController = TextEditingController();

  String selectedGender = 'Male';
  bool showDiscount = false;
  bool isLoading = false;
  bool _celebrationPlayed = false;
  bool _isSpinning = false;

  int? _finalSpinDiscount;
  int? _spinOfferValue;
  List<int> _spinValues = [];
  List<int> wheelNumbers = [];
  FixedExtentScrollController? _wheelController;

  // Animation controllers (lazy-initialized)
  AnimationController? _bulbController;
  AnimationController? _glowController;
  AnimationController? _discCardController;
  AnimationController? _bgController;

  Animation<double>? _glowAnim;
  Animation<double>? _discCardScale;
  Animation<double>? _discCardOpacity;

  @override
  void initState() {
    super.initState();
    _buildSpinValues();
  }

  // Initialize animations only when needed (lazy loading)
  void _initializeAnimations() {
    if (_bulbController != null) return; // Already initialized

    _bulbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 4.0, end: 22.0).animate(
      CurvedAnimation(parent: _glowController!, curve: Curves.easeInOut),
    );

    _discCardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _discCardScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _discCardController!, curve: Curves.elasticOut),
    );
    _discCardOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _discCardController!,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    birthdayController.dispose();
    anniversaryController.dispose();
    _bulbController?.dispose();
    _glowController?.dispose();
    _discCardController?.dispose();
    _bgController?.dispose();
    _wheelController?.dispose();
    super.dispose();
  }

  // ── Build spin values from API offers ──────────────────────
  void _buildSpinValues() {
    final Set<int> values = {0};
    for (var offer in widget.allOffers) {
      if (offer['offer_type'] == 'percent') {
        values.add((offer['offer_value'] as num).toInt());
      }
    }
    _spinValues = values.toList()..sort();
    if (_spinValues.length <= 1) _spinValues = [0, 5, 10, 15, 20, 25];
    wheelNumbers = List.from(_spinValues);
  }

  // ── Kick off spin then reveal discount ─────────────────────
  Future<void> _startSpinThenShowDiscount() async {
    _initializeAnimations(); // Initialize animations when needed
    final random = Random();
    final nonZeroValues = _spinValues.where((v) => v > 0).toList();
    final pool = nonZeroValues.isNotEmpty ? nonZeroValues : _spinValues;
    final int winner = pool[random.nextInt(pool.length)];
    _finalSpinDiscount = winner;
    _spinOfferValue = winner;
    await _showSpinDialog(winner);
    setState(() => showDiscount = true);
    _discCardController!.forward(from: 0);
    _triggerCelebration();
  }

  // ── Slot spin dialog ────────────────────────────────────────
  Future<void> _showSpinDialog(int targetPercent) async {
    if (_isSpinning) return;
    _isSpinning = true;

    final values = wheelNumbers;
    final int len = values.length;
    int targetIdx = values.indexOf(targetPercent);
    if (targetIdx == -1) targetIdx = values.indexOf(0);

    // Land in a middle repeat so we don't see the jump
    const int rotations = 14;
    final int targetItem = rotations * len + targetIdx;

    _wheelController = FixedExtentScrollController(initialItem: 0);
    final media = MediaQuery.of(context);
    final wheelH = (media.size.height * 0.38).clamp(250.0, 400.0);
    final itemH = (wheelH / 3.2).clamp(64.0, 96.0);
    final fontSize = (media.size.width * 0.11).clamp(26.0, 44.0);

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Spin',
      barrierColor: Colors.black.withOpacity(0.96),
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, a1, a2, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a1, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: a1, child: child),
        );
      },
      pageBuilder: (ctx, a1, a2) {
        bool _started = false;
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setS) {
              if (!_started) {
                _started = true;
                Future.delayed(const Duration(milliseconds: 500), () async {
                  try {
                    // Phase 1 — fast blur scroll
                    await _wheelController?.animateToItem(
                      (rotations - 4) * len,
                      duration: const Duration(milliseconds: 2400),
                      curve: Curves.fastLinearToSlowEaseIn,
                    );
                    // Phase 2 — decelerate to exact winner
                    await _wheelController?.animateToItem(
                      targetItem,
                      duration: const Duration(milliseconds: 2000),
                      curve: Curves.decelerate,
                    );
                    // Phase 3 — micro bounce
                    await _wheelController?.animateToItem(
                      targetItem + 1,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                    );
                    await _wheelController?.animateToItem(
                      targetItem,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.bounceOut,
                    );
                    if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                  } catch (_) {}
                });
              }

              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: media.size.width * 0.93,
                    maxHeight: media.size.height * 0.88,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          colors: [_kDeepRed, _kDarkRed],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: _kGold.withOpacity(0.2),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.85),
                            blurRadius: 50,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──────────────────────────────
                          _buildDialogHeader(),

                          // ── Slot machine ─────────────────────────
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Container(
                              width: double.infinity,
                              height: wheelH,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _kGold, width: 2.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: _kGold.withOpacity(0.3),
                                    blurRadius: 30,
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  // Background grid lines
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: SlotBackgroundPainter(),
                                    ),
                                  ),

                                  // Bulb columns
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: _buildBulbColumn(media, left: true),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: _buildBulbColumn(media, left: false),
                                  ),

                                  // Wheel
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 30,
                                        vertical: 10,
                                      ),
                                      child: SizedBox(
                                        height: wheelH - 20,
                                        child: ListWheelScrollView.useDelegate(
                                          controller: _wheelController,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemExtent: itemH,
                                          diameterRatio: 1.06,
                                          perspective: 0.002,
                                          overAndUnderCenterOpacity: 0.35,
                                          squeeze: 0.97,
                                          childDelegate:
                                              ListWheelChildLoopingListDelegate(
                                                children:
                                                    values
                                                        .map(
                                                          (v) => _buildSlotItem(
                                                            v,
                                                            fontSize: fontSize,
                                                            height: itemH,
                                                          ),
                                                        )
                                                        .toList(),
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Pulsing winner window
                                  Center(
                                    child: AnimatedBuilder(
                                      animation: _glowAnim!,
                                      builder:
                                          (_, __) => Container(
                                            height: itemH + 8,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _kGold,
                                                width: 2.5,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: _kGold.withOpacity(
                                                    0.9,
                                                  ),
                                                  blurRadius: _glowAnim!.value,
                                                  spreadRadius: 0,
                                                ),
                                              ],
                                            ),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // ── Footer ──────────────────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: null, // auto-spinning
                                    icon: const Icon(Icons.casino, size: 18),
                                    label: Text(
                                      'Spinning...',
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _kRed,
                                      disabledBackgroundColor: _kRed
                                          .withOpacity(0.6),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _kGold, width: 2),
                                  ),
                                  child: Text(
                                    'Good\nLuck!',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.poppins(
                                      color: _kGold,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    _wheelController?.dispose();
    _wheelController = null;
    _isSpinning = false;
  }

  // ── Dialog header with shimmer title ───────────────────────
  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_kGold, _kGold2, _kGold]),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(color: Colors.black38, offset: Offset(0, 3), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.casino, color: Color(0xFF3a0a00), size: 26),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _bulbController!,
            builder: (_, __) {
              // shimmer offset 0..1
              final s = _bulbController!.value;
              return ShaderMask(
                shaderCallback:
                    (bounds) => LinearGradient(
                      colors: const [
                        Color(0xFF7a3000),
                        Color(0xFFfff8e1),
                        Color(0xFF7a3000),
                      ],
                      stops: [
                        (s - 0.3).clamp(0.0, 1.0),
                        s.clamp(0.0, 1.0),
                        (s + 0.3).clamp(0.0, 1.0),
                      ],
                    ).createShader(bounds),
                child: Text(
                  'MEGA SPIN',
                  style: GoogleFonts.permanentMarker(
                    fontSize: 22,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          const Icon(Icons.casino, color: Color(0xFF3a0a00), size: 26),
        ],
      ),
    );
  }

  // ── Slot item tile ──────────────────────────────────────────
  Widget _buildSlotItem(
    int v, {
    required double fontSize,
    required double height,
  }) {
    final text = v == 0 ? '0%' : (v >= 1000 ? '₹$v' : '$v%');
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111111), Color(0xFF252525)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kGold.withOpacity(0.22), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback:
              (bounds) => const LinearGradient(
                colors: [_kGold, Colors.white, _kGold],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(bounds),
          child: Text(
            text,
            style: GoogleFonts.orbitron(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.8,
              shadows: const [
                Shadow(
                  color: Colors.black,
                  offset: Offset(2, 3),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bulb column (staggered sin-wave per bulb) ───────────────
  Widget _buildBulbColumn(MediaQueryData media, {required bool left}) {
    const count = 7;
    final size = (media.size.width * 0.022).clamp(6.0, 13.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final phase = (i / count) + (left ? 0.0 : 0.35);
        return AnimatedBuilder(
          animation: _bulbController!,
          builder: (_, __) {
            final wave =
                (sin((_bulbController!.value + phase) * 2 * pi) + 1) / 2;
            final color =
                Color.lerp(
                  const Color(0xFF8B0000),
                  const Color(0xFFFFD700),
                  wave,
                )!;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              width: size * 1.7,
              height: size * 1.7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.85 * wave),
                    blurRadius: 11 * wave,
                    spreadRadius: wave,
                  ),
                ],
                border: Border.all(
                  color: Colors.black.withOpacity(0.45),
                  width: 0.8,
                ),
              ),
            );
          },
        );
      }),
    );
  }

  // ── Date conversion ─────────────────────────────────────────
  String convertToISODate(String inputDate) {
    try {
      final parsed = DateFormat('dd-MM-yyyy').parseStrict(inputDate);
      return DateFormat('yyyy-MM-dd').format(parsed);
    } catch (_) {
      return inputDate;
    }
  }

  // ── Form submit ─────────────────────────────────────────────
  void _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    await _startSpinThenShowDiscount();
    final pickedValue = _spinOfferValue ?? 0;
    final userData = {
      'name': nameController.text,
      'phone': widget.phone,
      'birthday': convertToISODate(birthdayController.text),
      'anniversary': convertToISODate(anniversaryController.text),
      'gender': selectedGender,
      'offerType': 'percent',
      'offerValue': pickedValue.toString(),
      'offerId': null,
      'tableId': widget.tableCode ?? '',
    };
    try {
      final response = await http.post(
        Uri.parse('${dotenv.env['API_URL']}/crm/QR'),
        body: jsonEncode(userData),
        headers: {'Content-Type': 'application/json'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.statusCode == 200 || response.statusCode == 201
                ? 'Congratualations!'
                : 'Something went wrong!',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Celebration (vibrate + sound + confetti) ────────────────
  void _triggerCelebration() async {
    if (_celebrationPlayed) return;
    _celebrationPlayed = true;
    try {
      if (!kIsWeb && (await Vibration.hasVibrator() ?? false)) {
        Vibration.vibrate(pattern: [0, 200, 100, 300]);
      }
      if (!kIsWeb) {
        final player = AudioPlayer();
        await player.play(AssetSource('assets/sounds/notification.mp3'));
      } else {
        discount_sound_web.triggerCelebrationWeb();
      }
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder:
              (_) => const ConfettiOverlay(durationMs: 2800, particleCount: 50),
        );
        Future.delayed(const Duration(milliseconds: 2800), () {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        });
      }
    } catch (_) {}
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final phoneController = TextEditingController(text: widget.phone);

    return Scaffold(
      backgroundColor: Colors.white,
      body:
          isLoading
              ? Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.black,
                  size: 42,
                ),
              )
              : showDiscount
              ? _buildDiscountScreen()
              : SafeArea(child: _buildForm(phoneController, media)),
    );
  }

  // ── Form screen ──────────────────────────────────────────────
  Widget _buildForm(TextEditingController phoneCtrl, MediaQueryData media) {
    final hPad = (media.size.width * 0.06).clamp(12.0, 28.0);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        children: [
          _buildHeader(media),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 22),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildSectionTitle('Personal Details'),
                  const SizedBox(height: 12),
                  _buildDisabledTextField(
                    label: 'Phone Number',
                    controller: phoneCtrl,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Name',
                    controller: nameController,
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 14),
                  _buildGenderSelector(),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Dates'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateField(
                          'Birthday',
                          birthdayController,
                          isRequired: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildDateField(
                          'Anniversary',
                          anniversaryController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _submitForm,
                      icon: const Icon(Icons.casino_outlined),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      label: Text(
                        'Submit & Spin!',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You won't be able to edit details later.",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(MediaQueryData media) {
    final iconSz = (media.size.width * 0.12).clamp(44.0, 64.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_kGreen, _kGreenDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.card_giftcard, size: iconSz, color: Colors.white),
          const SizedBox(height: 8),
          Text(
            'Claim Your Offer!',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Complete your profile to unlock rewards',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      title,
      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  Widget _buildDisabledTextField({
    required String label,
    required TextEditingController controller,
  }) {
    return TextFormField(
      controller: controller,
      enabled: false,
      style: GoogleFonts.poppins(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(),
        filled: true,
        fillColor: Colors.grey[200],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    IconData? icon,
  }) {
    return TextFormField(
      controller: controller,
      style: GoogleFonts.poppins(fontSize: 13),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        labelStyle: GoogleFonts.poppins(fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children:
            ['Male', 'Female'].map((g) {
              final sel = selectedGender == g;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => selectedGender = g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? _kGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      g,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: sel ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildDateField(
    String label,
    TextEditingController ctrl, {
    bool isRequired = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        DateInputFormatter(),
      ],
      style: GoogleFonts.poppins(fontSize: 13),
      validator: (v) {
        if (isRequired && (v == null || v.isEmpty)) return 'Required';
        if (v != null && v.isNotEmpty) {
          if (!RegExp(r'^\d{2}-\d{2}-\d{4}$').hasMatch(v))
            return 'Enter dd-mm-yyyy';
          try {
            DateFormat('dd-MM-yyyy').parseStrict(v);
          } catch (_) {
            return 'Invalid date';
          }
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: 'dd-mm-yyyy',
        labelStyle: GoogleFonts.poppins(fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: const Icon(Icons.calendar_today, size: 20),
      ),
    );
  }

  // ── Discount result screen ───────────────────────────────────
  Widget _buildDiscountScreen() {
    final media = MediaQuery.of(context);
    final discount = _finalSpinDiscount ?? 0;
    final won = discount > 0;

    return AnimatedBuilder(
      animation: _bgController!,
      builder: (_, child) {
        final t = _bgController!.value;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(
                  const Color(0xFF005A4A),
                  const Color(0xFF007B67),
                  t,
                )!,
                Color.lerp(
                  const Color(0xFF00A884),
                  const Color(0xFF00CC99),
                  t,
                )!,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: child,
        );
      },
      child: Stack(
        children: [
          // Radial glow overlay
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _glowController!,
                builder:
                    (_, __) => Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.5),
                          radius: 0.9,
                          colors: [
                            Colors.white.withOpacity(
                              0.08 * _glowController!.value,
                            ),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    won ? '🎉  CONGRATULATIONS!' : 'Better Luck Next Time',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: (media.size.width * 0.076).clamp(22.0, 38.0),
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),

                  const SizedBox(height: 10),
                  Text(
                    won
                        ? 'You just unlocked a discount!'
                        : 'Thanks for playing — come back soon!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Discount card — spring bounce in
                  ScaleTransition(
                    scale: _discCardScale!,
                    child: FadeTransition(
                      opacity: _discCardOpacity!,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 28,
                          horizontal: 32,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.22),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Decorative dots row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(
                                5,
                                (i) => Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: (i % 2 == 0) ? _kGreenDark : _kGold,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Your Discount',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ShaderMask(
                              shaderCallback:
                                  (bounds) => const LinearGradient(
                                    colors: [_kGreenDark, _kGreen],
                                  ).createShader(bounds),
                              child: Text(
                                won ? '$discount%' : '0%',
                                style: GoogleFonts.orbitron(
                                  fontSize: (media.size.width * 0.18).clamp(
                                    52.0,
                                    80.0,
                                  ),
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              won
                                  ? 'OFF on your total bill'
                                  : 'Try again next visit',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: List.generate(
                                5,
                                (i) => Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: (i % 2 == 0) ? _kGold : _kGreenDark,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 48,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                    ),
                    child: Text(
                      'Continue',
                      style: GoogleFonts.poppins(
                        color: _kGreenDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confetti overlay ─────────────────────────────────────────
class ConfettiOverlay extends StatefulWidget {
  final int durationMs;
  final int particleCount;
  const ConfettiOverlay({
    Key? key,
    this.durationMs = 2800,
    this.particleCount = 50,
  }) : super(key: key);
  @override
  _ConfettiOverlayState createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final Random _rnd = Random();
  final List<_ConfettiParticle> _particles = [];

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(
            vsync: this,
            duration: Duration(milliseconds: widget.durationMs),
          )
          ..addListener(() => setState(() {}))
          ..forward();
    for (int i = 0; i < widget.particleCount; i++) {
      _particles.add(
        _ConfettiParticle(
          offsetX: _rnd.nextDouble(),
          startY: -0.08 - _rnd.nextDouble() * 0.25,
          size: 5.0 + _rnd.nextDouble() * 11.0,
          color: Colors.primaries[_rnd.nextInt(Colors.primaries.length)]
              .withOpacity(0.95),
          rotate: _rnd.nextDouble() * pi,
          drift: (_rnd.nextDouble() - 0.5) * 0.12,
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ConfettiPainter(_particles, _ctrl.value),
        size: Size.infinite,
      ),
    );
  }
}

class _ConfettiParticle {
  final double offsetX, startY, size, rotate, drift;
  final Color color;
  _ConfettiParticle({
    required this.offsetX,
    required this.startY,
    required this.size,
    required this.color,
    required this.rotate,
    required this.drift,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double t;
  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var p in particles) {
      final x = (p.offsetX + p.drift * t) * size.width;
      final y = (p.startY + t * (1.5 + p.offsetX * 0.5)) * size.height;
      final s = p.size * (0.5 + 0.5 * sin(t * pi * 2.2 + p.rotate));
      final alpha = (1.0 - (t * 0.7)).clamp(0.0, 1.0);
      paint.color = p.color.withOpacity(alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotate * (0.4 + t * 2));
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.55),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

// ── Slot background painter ───────────────────────────────────
class SlotBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFFFFD700).withOpacity(0.05);
    const rows = 14;
    for (int i = 0; i <= rows; i++) {
      final y = (size.height / rows) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // vertical accent lines
    const cols = 6;
    final linePaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0xFFFFD700).withOpacity(0.03);
    for (int i = 0; i <= cols; i++) {
      final x = (size.width / cols) * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}
