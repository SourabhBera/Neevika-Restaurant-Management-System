import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ExistingUserDetailsScreen extends StatelessWidget {
  final Map<dynamic, dynamic> customer;

  const ExistingUserDetailsScreen({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F1),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with gradient background
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4CAF50), Color(0xFF007B67)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.shade300.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                      width: 75,
                      height: 75,
                      decoration: const BoxDecoration(
                        color: Colors.white, // Fill rest of space with white
                        shape: BoxShape.circle, // Keeps it circular
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'lib/assets/5k_logo.jpeg',
                          fit: BoxFit.contain, // Image scales proportionally
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    "Welcome back!",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    customer['name'] ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Info Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(20),
                shadowColor: Colors.black12,
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 56),
                      const SizedBox(height: 20),
                      Text(
                        "Looks like we already have your details!",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 24),

                      _buildInfoRow(Icons.person_2_rounded, "Name", customer['name']),
                      _buildInfoRow(Icons.phone_rounded, "Phone", customer['phone']),
                      _buildInfoRow(Icons.email_outlined, "Email", customer['email']),
                      _buildInfoRow(Icons.transgender, "Gender", customer['gender']),
                      _buildInfoRow(Icons.cake_outlined, "Birthday", customer['birthday']),
                      _buildInfoRow(Icons.location_on_outlined, "Address", customer['address']),
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(),

            // Button
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24),
            //   child: ElevatedButton.icon(
            //     onPressed: () {
            //       Navigator.pop(context);
            //     },
            //     icon: const Icon(Icons.local_offer, size: 24),
            //     label: Text(
            //       "Enjoy your 10% discount!",
            //       style: GoogleFonts.poppins(
            //         fontWeight: FontWeight.w700,
            //         fontSize: 16,
            //       ),
            //     ),
            //     style: ElevatedButton.styleFrom(
            //       backgroundColor: const Color(0xFF00A884),
            //       padding: const EdgeInsets.symmetric(vertical: 16),
            //       shape: RoundedRectangleBorder(
            //         borderRadius: BorderRadius.circular(14),
            //       ),
            //       elevation: 6,
            //       shadowColor: Colors.greenAccent.shade700,
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF00A884)),
          const SizedBox(width: 12),
          Text(
            "$label:",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 15,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
