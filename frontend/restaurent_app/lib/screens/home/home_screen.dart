import 'dart:convert';
import 'package:Neevika/screens/Drinks/drinksOrders/testPage.dart';
import 'package:Neevika/screens/home/AttendanceScreen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:Neevika/screens/Home/MyOrdersScreen.dart';
import 'package:Neevika/screens/Home/ScoreboardSceen.dart';
import 'package:Neevika/screens/Home/UserInformation_Screen.dart';
import 'package:Neevika/widgets/sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? userId;
  String? userRole;

  @override
  void initState() {
    super.initState();
    fetchUserId();
  }

  Future<void> fetchUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwtToken');

      if (token == null) {
        print('No token found. User might not be logged in.');
        return;
      }

      final decodedToken = JwtDecoder.decode(token);
      final id = decodedToken['id'];
      final role = decodedToken['role'];
      print("\n\nUser Details: $role\n\n");

      setState(() {
        userId = id.toString();
        userRole = role.toString();
      });

    } catch (e) {
      print("Error fetching User Details: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      drawer: const Sidebar(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Check screen width to adjust layout for larger screens
                  bool isWideScreen = constraints.maxWidth > 600;

                  return Column(
                    children: [
                      // Top Icon with text
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'lib/assets/Neevika_logo.jpg',
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover, // Adjust this depending on how you want the logo to scale
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '5k Family Resto & Bar',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 30),

                      Container(
                        margin: EdgeInsets.symmetric(horizontal: isWideScreen ? 40 : 24),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Quick Access',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Quick Access Grid
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: isWideScreen ? 40 : 20),
                        child: GridView.count(
                          shrinkWrap: true,
                          crossAxisCount: isWideScreen ? 4 : 2, // More items horizontally on wider screens
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          physics: NeverScrollableScrollPhysics(),
                          childAspectRatio: isWideScreen ? 1.5 : 1.3,
                          children: [
                            QuickAccessCard(title: "My Information", icon: Icons.info_outline, onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => MyInformationScreen(userId: userId!)),
                              );
                            }),
                            QuickAccessCard(
                              title: "My Orders",
                              icon: Icons.shopping_cart_outlined,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => MyOrdersScreen(userId: userId!),),
                                );
                              },
                            ),
                            QuickAccessCard(
                              title: "ScoreBoard",
                              icon: Icons.emoji_events_outlined,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => ScoreboardScreen()),
                                  // MaterialPageRoute(builder: (context) => PrintTestPage()),
                                );
                              },
                            ),
                            QuickAccessCard(title: "Attendance", icon: Icons.notifications_none, onTap: () {Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => UserAttendanceScreen(employeeId: userId!)),
                              );}),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      // More Options
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: isWideScreen ? 40 : 20),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0, bottom: 8),
                              child: Text(
                                "More Options",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (userRole == 'Admin') ...[
                              ListTile(
                                leading: Icon(Icons.summarize, color: Color(0xFF7B61FF)),
                                title: Text('Day End Summary', style: GoogleFonts.poppins(fontSize: 11.3)),
                                onTap: () {
                                  Navigator.pushNamed(context, '/day-end-summary');
                                },
                              ),
                              ListTile(
                                leading: Icon(Icons.dashboard, color: Color(0xFF7B61FF)),
                                title: Text('Dashboard', style: GoogleFonts.poppins(fontSize: 11.3)),
                                onTap: () {
                                  Navigator.pushNamed(context, '/Dashboard');
                                },
                              ),
                              ListTile(
                                leading: Icon(Icons.event_available, color: Color(0xFF7B61FF)),
                                title: Text('Attendance', style: GoogleFonts.poppins(fontSize: 11.3)),
                                onTap: () {
                                  Navigator.pushNamed(context, '/attendance');
                                },
                              ),
                            ] else if (userRole == 'Waiter') ...[
                              ListTile(
                                leading: Icon(Icons.restaurant_menu, color: Color(0xFF7B61FF)),
                                title: Text('Menu', style: GoogleFonts.poppins(fontSize: 11.3)),
                                onTap: () {
                                  Navigator.pushNamed(context, '/menu');
                                },
                              ),
                              ListTile(
                                leading: Icon(Icons.local_bar, color: Color(0xFF7B61FF)),
                                title: Text('Drinks Menu', style: GoogleFonts.poppins(fontSize: 11.3)),
                                onTap: () {
                                  Navigator.pushNamed(context, '/drinks');
                                },
                              ),
                            ] else if (userRole == 'Chef') ...[
                              ListTile(
                                leading: Icon(Icons.receipt_long, color: Color(0xFF7B61FF)),
                                title: Text('Order', style: GoogleFonts.poppins(fontSize: 11.3)),
                                onTap: () {
                                  Navigator.pushNamed(context, '/orders');
                                },
                              ),
                              ListTile(
                                leading: Icon(Icons.wine_bar, color: Color(0xFF7B61FF)),
                                title: Text('Drinks Order', style: GoogleFonts.poppins(fontSize: 11.3)),
                                onTap: () {
                                  Navigator.pushNamed(context, '/drink-orders');
                                },
                              ),
                            ],

                            // Always shown logout option
                            ListTile(
                              leading: Icon(Icons.logout, color: Color.fromARGB(255, 255, 97, 97)),
                              title: Text('Logout', style: GoogleFonts.poppins(fontSize: 11.3, color: Color.fromARGB(255, 255, 97, 97))),
                              onTap: () {
                                Navigator.pushNamed(context, '/logout');
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickAccessCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const QuickAccessCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 23, color: Color(0xFF7B61FF)),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
