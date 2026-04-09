import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  String? userRole;
  int? userId;
  String? userName;

  @override
  void initState() {
    super.initState();
    _loadTokenData();
  }

  Future<void> _loadTokenData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');

    if (token == null) {
      print('No token found. User might not be logged in.');
      return;
    }

    debugPrint("token: $token");

    final decodedToken = JwtDecoder.decode(token);
    debugPrint("tokenData: $decodedToken");
    userId = decodedToken['id'];
    userRole = decodedToken['role'];
    userName = decodedToken['userName'];
    print('User Role: $userRole');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF000000), Color(0xFF333333)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'lib/assets/5k_logo.jpeg',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '5K Restro & Bar',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  userName ?? 'Unknown User',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),


          // if(userRole == 'Admin')
          _buildListTile(context, LucideIcons.home, 'Home', '/home'),


          if (userRole == 'Admin')
            _buildListTile(
              context,
              LucideIcons.layoutGrid,
              'Dashboard',
              '/Dashboard',
            ),



          //DAILY OPERATIONS
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Partners' ||
              userRole == 'Acting Restaurant Manager')
            ExpansionTile(
              collapsedIconColor: Colors.black54,
              iconColor: Colors.black87,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
              leading: Icon(
                LucideIcons.activitySquare,
                size: 18,
                color: Colors.blueGrey,
              ),
              title: Text(
                'Daily Operations',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              children: [
                if (userRole == 'Admin' ||
                    userRole == 'Partners' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager')
                  _buildSubListTile(
                    context,
                    LucideIcons.listOrdered,
                    'Running Orders',
                    '/running-orders',
                  ),

                if (userRole == 'Admin')
                  _buildSubListTile(
                    context,
                    LucideIcons.dollarSign,
                    "Today's Sale",
                    '/todays-sales',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Partners' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Store Keeper' ||
                    userRole == 'Acting Restaurant Manager')
                  _buildSubListTile(
                    context,
                    LucideIcons.box,
                    'Low Stock',
                    '/low-stock',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Partners' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager')
                  _buildSubListTile(
                    context,
                    LucideIcons.creditCard,
                    'Vendor Payment',
                    '/vendor-payment',
                  ),

                if (userRole == 'Admin')
                  _buildSubListTile(
                    context,
                    LucideIcons.barChart3,
                    'Profit & Loss',
                    '/profit-loss',
                  ),
              ],
            ),



          //INVENTORY
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Accountant' ||
              userRole == 'Acting Restaurant Manager')
            ExpansionTile(
              collapsedIconColor: Colors.black54,
              iconColor: Colors.black87,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
              leading: Icon(
                LucideIcons.warehouse,
                size: 18,
                color: Colors.blueGrey,
              ),
              title: Text(
                'Inventory',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              children: [
                if (userRole == 'Admin' ||
                    userRole == 'Partners' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Store Keeper' ||
                    userRole == 'Accountant' ||
                    userRole == 'Acting Restaurant Manager')
                  _buildSubListTile(
                    context,
                    LucideIcons.warehouse,
                    'Main Inventory',
                    '/inventory',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Partners' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Store Keeper' ||
                    userRole == 'Acting Restaurant Manager')
                  _buildSubListTile(
                    context,
                    LucideIcons.chefHat,
                    "Kitchen Inventory",
                    '/kitchen_inventory',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Partners' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Store Keeper' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.wine,
                    'Drinks Main Inventory',
                    '/drinks-inventory',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Partners' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Store Keeper')
                  _buildSubListTile(
                    context,
                    LucideIcons.beer,
                    'Drinks Kitchen Inventory',
                    '/drinks-kitchen_inventory',
                  ),
              ],
            ),



          //MENU
          ExpansionTile(
            collapsedIconColor: Colors.black54,
            iconColor: Colors.black87,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
            leading: Icon(
              LucideIcons.bookOpen,
              size: 18,
              color: Colors.blueGrey,
            ),
            title: Text(
              'Menu',
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            children: [
              if (userRole == 'Admin' ||
                  userRole == 'Partners' ||
                  userRole == 'Restaurant Manager' ||
                  userRole == 'Acting Restaurant Manager' ||
                  userRole == 'Captain' ||
                  userRole == 'Steward')
                _buildSubListTile(
                  context,
                  LucideIcons.menu,
                  'Food Menu',
                  '/menu',
                ),


              if (userRole == 'Admin' ||
                  userRole == 'Partners' ||
                  userRole == 'Acting Restaurant Manager' ||
                  userRole == 'Restaurant Manager' ||
                  userRole == 'Captain' ||
                  userRole == 'Steward')
                _buildSubListTile(
                  context,
                  LucideIcons.wine,
                  "Drinks Menu",
                  '/drinks',
                ),


              if (userRole == 'Admin' ||
                  userRole == 'Partners' ||
                  userRole == 'Restaurant Manager' ||
                  userRole == 'Acting Restaurant Manager' ||
                  userRole == 'Main Chef' ||
                  userRole == 'Assistant Chef' ||
                  userRole == 'Store Keeper' ||
                  userRole == 'Purchase Head')
                _buildSubListTile(
                  context,
                  LucideIcons.receipt,
                  'Food Orders',
                  '/orders',
                ),


              // if (userRole == 'Admin' ||
              //     userRole == 'Partners' ||
              //     userRole == 'Restaurant Manager' ||
              //     userRole == 'Acting Restaurant Manager' ||
                  
              //     userRole == 'Store Keeper' ||
              //     userRole == 'Purchase Head')
              //   _buildSubListTile(
              //     context,
              //     LucideIcons.receipt,
              //     'Foods Canceled Orders',
              //     '/food-canceled-orders',
              //   ),



              if (userRole == 'Admin' ||
                  userRole == 'Partners' ||
                  userRole == 'Restaurant Manager' ||
                  
                  userRole == 'Acting Restaurant Manager' ||
                  userRole == 'Bartender')
                _buildSubListTile(
                  context,
                  LucideIcons.cupSoda,
                  'Drinks Orders',
                  '/drink-orders',
                ),


              // if (userRole == 'Admin' ||
              //     userRole == 'Partners' ||
                  
              //     userRole == 'Acting Restaurant Manager' ||
              //     userRole == 'Restaurant Manager' ||
              //     userRole == 'Bartender')
              //   _buildSubListTile(
              //     context,
              //     LucideIcons.cupSoda,
              //     'Drinks Canceled Orders',
              //     '/drink-canceled-orders',
              //   ),


              // if (userRole == 'Admin' ||
              //     userRole == 'Partners' ||
              //     userRole == 'Restaurant Manager' ||
              //     userRole == 'Main Chef' ||
              //     userRole == 'Assistant Chef')
              //   _buildSubListTile(
              //     context,
              //     LucideIcons.leaf,
              //     'Food Menu-Ingredients',
              //     '/menu-ingredients',
              //   ),

              // if (userRole == 'Admin' ||
              //     userRole == 'Partners' ||
              //     userRole == 'Restaurant Manager')
              //   _buildSubListTile(
              //     context,
              //     LucideIcons.flaskConical,
              //     'Drinks Menu-Ingredients',
              //     '/drinks-menu-ingredients',
              //   ),
            ],
          ),




          //Reports
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Acting Restaurant Manager' ||
              userRole == 'Owner')
            ExpansionTile(
              collapsedIconColor: Colors.black54,
              iconColor: Colors.black87,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
              leading: Icon(
                LucideIcons.fileBarChart,
                size: 18,
                color: Colors.blueGrey,
              ),
              title: Text(
                'Reports',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              children: [
                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Owner')
                  _buildSubListTile(
                    context,
                    LucideIcons.fileText,
                    'Day End Summary',
                    '/day-end-summary',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Owner')
                  _buildSubListTile(
                    context,
                    LucideIcons.fileSearch,
                    "Other Reports",
                    '/other-reports',
                  ),
              ],
            ),




          //Management
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Accountant' ||
              userRole == 'Partners' ||
              userRole == 'HR' ||
              userRole == 'Acting Restaurant Manager')
            ExpansionTile(
              collapsedIconColor: Colors.black54,
              iconColor: Colors.black87,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
              leading: Icon(
                LucideIcons.briefcase,
                size: 18,
                color: Colors.blueGrey,
              ),
              title: Text(
                'Management',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              children: [
                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.calculator,
                    "Accounting",
                    '/expense',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'HR' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.user2,
                    "User Management",
                    '/manage-users',
                  ),
                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'HR' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.user2,
                    "User Roles",
                    '/user-roles',
                  ),


                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'HR' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.user2,
                    "Approve Users",
                    '/unverified-users',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'HR' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.userPlus,
                    "Register User",
                    '/register',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'HR' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.keyRound,
                    "Change User Password",
                    '/change-password',
                  ),

                // if(userRole == 'Admin' || userRole=='Restaurant Manager')
                // _buildSubListTile(context, LucideIcons.clipboardCheck, "User Logs", '/under_construction'),
              ],
            ),




          //CRM
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Acting Restaurant Manager' ||
              userRole == 'Partners' ||
              userRole == 'Captain' ||
              userRole == 'Steward')
            ExpansionTile(
              collapsedIconColor: Colors.black54,
              iconColor: Colors.black87,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
              leading: Icon(
                LucideIcons.megaphone,
                size: 18,
                color: Colors.blueGrey,
              ),
              title: Text(
                'CRM',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              children: [
                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners')
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: ExpansionTile(
                      leading: const Icon(LucideIcons.messageCircle, size: 18),
                      title: Text(
                        'WhatsApp Marketing',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        _buildSubListTile(
                          context,
                          LucideIcons.barChart,
                          'Campaign Reports',
                          '/customer-details',
                        ),
                        _buildSubListTile(
                          context,
                          LucideIcons.percent,
                          'Offer Management',
                          '/offer-management',
                        ),
                      ],
                    ),
                  ),

                // if(userRole == 'Admin' || userRole=='Restaurant Manager' || userRole=='Partners')
                // _buildSubListTile(context, LucideIcons.contact, "Customer Details", '/customer-details'),
                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'Captain' ||
                    userRole == 'Steward' ||
                    userRole == 'Billing Team')
                  _buildSubListTile(
                    context,
                    LucideIcons.gift,
                    "Verify Phone Number",
                    '/verify-phone-number',
                  ),
              ],
            ),





          // //HR
          // if (userRole == 'Admin' ||
          //     userRole == 'Restaurant Manager' ||
          //     userRole == 'Acting Restaurant Manager' ||
          //     userRole == 'Partners' ||
          //     userRole == 'Accountant')
          //   ExpansionTile(
          //     collapsedIconColor: Colors.black54,
          //     iconColor: Colors.black87,
          //     tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          //     childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
          //     leading: Icon(
          //       LucideIcons.userCog,
          //       size: 18,
          //       color: Colors.blueGrey,
          //     ),
          //     title: Text(
          //       'HR',
          //       style: GoogleFonts.poppins(
          //         fontSize: 11.5,
          //         fontWeight: FontWeight.w600,
          //         color: Colors.black87,
          //       ),
          //     ),
          //     children: [
          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'HR' ||
          //           userRole == 'Accountant' ||
          //           userRole == 'Billing Team')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.calendarCheck2,
          //           "Attendance",
          //           '/attendance',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'HR' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.graduationCap,
          //           "Training",
          //           '/training',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'HR' ||
          //           userRole == 'Accountant' ||
          //           userRole == 'Billing Team')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.users,
          //           "Staff",
          //           '/staff',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'HR' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.wallet,
          //           "Payroll",
          //           '/payroll',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'HR' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.fileText,
          //           "Appointment",
          //           '/appointment-letter',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'HR' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.calendarMinus,
          //           "Leaves Application",
          //           '/leave-letter',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'HR' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.trophy,
          //           "Leaderboard",
          //           '/scoreboard',
          //         ),

          //       // if(userRole == 'Admin' || userRole=='Restaurant Manager')
          //       // _buildSubListTile(context, LucideIcons.clipboardCheck, "Incentives", '/under_construction'),
          //     ],
          //   ),





          //Vendor
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Acting Restaurant Manager' ||
              userRole == 'Partners' ||
              userRole == 'Purchase Head' ||
              userRole == 'Accountant')
            ExpansionTile(
              collapsedIconColor: Colors.black54,
              iconColor: Colors.black87,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
              leading: Icon(
                LucideIcons.truck,
                size: 18,
                color: Colors.blueGrey,
              ),
              title: Text(
                'Vendor',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              children: [
                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'Purchase Head' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.truck,
                    "Vendor",
                    '/vendor',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'Purchase Head' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.shoppingCart,
                    "Purchases",
                    '/purchase',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'Purchase Head' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.calendarClock,
                    "Payment Schedule",
                    '/vendor-payment',
                  ),

                if (userRole == 'Admin' ||
                    userRole == 'Restaurant Manager' ||
                    userRole == 'Acting Restaurant Manager' ||
                    userRole == 'Partners' ||
                    userRole == 'Purchase Head' ||
                    userRole == 'Accountant')
                  _buildSubListTile(
                    context,
                    LucideIcons.receipt,
                    "Receipt",
                    '/vendor-payment',
                  ),
              ],
            ),




          // //Accounting
          // if (userRole == 'Admin' ||
          //     userRole == 'Restaurant Manager' ||
          //     userRole == 'Acting Restaurant Manager' ||
          //     userRole == 'Partners' ||
          //     userRole == 'Accountant')
          //   ExpansionTile(
          //     collapsedIconColor: Colors.black54,
          //     iconColor: Colors.black87,
          //     tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          //     childrenPadding: const EdgeInsets.only(left: 12, bottom: 5),
          //     leading: Icon(
          //       LucideIcons.banknote,
          //       size: 18,
          //       color: Colors.blueGrey,
          //     ),
          //     title: Text(
          //       'Accounting',
          //       style: GoogleFonts.poppins(
          //         fontSize: 11.5,
          //         fontWeight: FontWeight.w600,
          //         color: Colors.black87,
          //       ),
          //     ),
          //     children: [
          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.dollarSign,
          //           "Sales",
          //           '/todays-sales',
          //         ),

          //       // if(userRole == 'Admin' || userRole=='Restaurant Manager')
          //       // _buildSubListTile(context, LucideIcons.clipboardCheck, "Other Sales", '/under_construction'),
          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.creditCard,
          //           "Expenses",
          //           '/expense',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.shoppingBag,
          //           "Purchase",
          //           '/purchase',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners' ||
          //           userRole == 'Accountant')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.wallet,
          //           "Payroll",
          //           '/payroll',
          //         ),

          //       if (userRole == 'Admin' ||
          //           userRole == 'Restaurant Manager' ||
          //           userRole == 'Acting Restaurant Manager' ||
          //           userRole == 'Partners')
          //         _buildSubListTile(
          //           context,
          //           LucideIcons.barChart3,
          //           "Profit & Loss",
          //           '/profit-loss',
          //         ),
          //     ],
          //   ),






          // TABLES & BILLS
          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Acting Restaurant Manager' ||
              userRole == 'Partners' ||
              userRole == 'Billing Team' ||
              userRole == 'Captain' ||
              userRole == 'Steward' ||
              userRole == 'Owner')
            _buildListTile(
              context,
              LucideIcons.layoutPanelLeft,
              "Tables",
              '/tables',
            ),

          if (userRole == 'Admin' ||
              userRole == 'Restaurant Manager' ||
              userRole == 'Acting Restaurant Manager' ||
              userRole == 'Partners' ||
              userRole == 'Billing Team')
            _buildListTile(
              context,
              LucideIcons.layoutPanelLeft,
              "Bills",
              '/bills',
            ),  


            //Compliemnetary Profiles
            _buildListTile(
              context,
              LucideIcons.layoutPanelLeft,
              "Compliemnetary Profiles",
              '/compliemnetary-profiles',
            ),



          // //Incident Report
          // _buildListTile(
          //   context,
          //   LucideIcons.clipboardCheck,
          //   "Incident Report",
          //   '/incident-report',
          // ),


          // _buildListTile(context, LucideIcons.clipboardCheck, "Restuarant Profile", '/under_construction'),
          // _buildListTile(context, LucideIcons.clipboardCheck, "T & C", '/under_construction'),
          _buildListTile(
            context,
            LucideIcons.trash,
            'Delete Account',
            '/delete-account',
            isLogout: true,
          ),
          _buildListTile(
            context,
            LucideIcons.logOut,
            'Logout',
            '/logout',
            isLogout: true,
          ),
          SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context,
    IconData icon,
    String title,
    String route, {
    bool isLogout = false,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(
        icon,
        color: isLogout ? Colors.redAccent : Colors.black87,
        size: 20,
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isLogout ? Colors.redAccent : Colors.black87,
        ),
      ),
      hoverColor: Colors.grey.shade100,
      onTap: () {
        if (isLogout) {
          Navigator.pushNamedAndRemoveUntil(context, route, (route) => false);
        } else {
          Navigator.pushNamed(context, route);
        }
      },
    );
  }

  Widget _buildSubListTile(
    BuildContext context,
    IconData icon,
    String title,
    String route,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: Colors.grey.shade300, width: 2),
          ),
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 20, right: 10),
          leading: Icon(icon, size: 16, color: Colors.grey[700]),
          title: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
          onTap: () => Navigator.pushNamed(context, route),
        ),
      ),
    );
  }
}
