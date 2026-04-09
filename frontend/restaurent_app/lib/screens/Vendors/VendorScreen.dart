import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:Neevika/screens/Vendors/VendorAddScreen.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:Neevika/screens/Vendors/VendorDetailsScreen.dart';
import 'package:Neevika/screens/Vendors/VendorEditScreen.dart';

class ViewVendorScreen extends StatefulWidget {
  const ViewVendorScreen({super.key});

  @override
  State<ViewVendorScreen> createState() => _ViewVendorScreenState();
}

class _ViewVendorScreenState extends State<ViewVendorScreen> {
  List<dynamic> vendors = [];
  List<dynamic> filteredVendors = [];
  bool isLoading = true;
  String searchQuery = '';
  bool hasErrorOccurred = false;

  @override
  void initState() {
    super.initState();
    fetchVendors();
  }

  Future<void> fetchVendors() async {
    try {
      final response = await http
          .get(Uri.parse('${dotenv.env['API_URL']}/vendor/'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        setState(() {
          vendors = json.decode(response.body);
          filteredVendors = vendors;
          isLoading = false;
          hasErrorOccurred = false;
        });
      } else {
        await Future.delayed(const Duration(seconds: 4));
        setState(() {
          isLoading = false;
          hasErrorOccurred = true;
        });
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 4));
      setState(() {
        isLoading = false;
        hasErrorOccurred = true;
      });
      print('Error fetching vendors: $e');
    }
  }

  // Filter vendors based on search query
  void filterVendor(String query) {
    final lowerQuery = query.toLowerCase();
    List<dynamic> filteredItems =
        vendors.where((vendor) {
          final name = vendor['name']?.toString().toLowerCase() ?? '';
          final work = vendor['work']?.toString().toLowerCase() ?? '';
          final email = vendor['email']?.toString().toLowerCase() ?? '';
          return name.contains(lowerQuery) ||
              work.contains(lowerQuery) ||
              email.contains(lowerQuery);
        }).toList();

    setState(() {
      filteredVendors = filteredItems;
    });
  }

  Widget buildVendorCard(dynamic vendor) {
  
    return Container(
      margin: const EdgeInsets.all(12),
      width: MediaQuery.of(context).size.width * 0.89,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E5E5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Name + Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  vendor['name']?.toString() ?? 'Vendor Name',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1917),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE44D26),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  vendor['status']?.toString() ?? 'Active',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          Text(
            vendor['business_type']?.toString() ?? 'Vendor Type',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF78726D),
            ),
          ),
          const SizedBox(height: 16),

          // Contact Details
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: "Contact: ",
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                TextSpan(
                  text: vendor['contact_person'] ?? 'N/A',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: "Email: ",
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                TextSpan(
                  text: vendor['email'] ?? 'N/A',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: "Phone: ",
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                TextSpan(
                  text: vendor['phone'] ?? 'N/A',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Edit Button
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => VendorDetailsScreen(vendor: vendor, purchaseHistories: {},),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF8F5F2),
                    side: const BorderSide(color: Color(0xFFE5E5E5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    "View Details",
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditVendorScreen(vendor: vendor),
                      ),
                    ).then((_) {
                      fetchVendors();
                    });
                  },
                  icon: const Icon(
                    Icons.edit,
                    size: 16,
                    color: Color(0xFF1C1917),
                  ),
                  label: Text(
                    "Edit",
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF8F5F2),
                    side: const BorderSide(color: Color(0xFFE5E5E5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Build search bar
  Widget buildSearchBar() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.89,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextField(
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.black, // Updated text color for visibility
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8F5F2), // Background color
            hintText: 'Search Vendors...',
            hintStyle: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF1C1917), // Hint text color
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: Color(0xFF1C1917), // Icon color
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 204, 203, 203),
                width: 1.3,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFFE5E5E5),
                width: 1.5,
              ),
            ),
          ),
          onChanged: (value) {
            setState(() {
              searchQuery = value;
              filterVendor(value);
            });
          },
        ),
      ),
    );
  }

  // Build the button below the search bar
  Widget buildAddButton() {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.89, 
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 12,
        ), 
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AddVendorScreen()),
            ).then((_) {
              fetchVendors();
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFFD95326), // Red background color
            elevation: 0, // No elevation (flat button)
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            minimumSize: const Size.fromHeight(50),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add, // Add icon
                color: Colors.white, // White icon color
              ),
              SizedBox(width: 8), // Space between icon and text
              Text(
                'Add Vendor', // Text on the button
                style: GoogleFonts.poppins(
                  color: Colors.white, // White text color
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vendors',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage your supplies and vendors',
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.black54),
            ),
          ],
        ),
      ),

      body:
          isLoading
              ? Center(
                child: LoadingAnimationWidget.staggeredDotsWave(
                  color: Colors.black,
                  size: 40,
                ),
              )
              : hasErrorOccurred
              ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 60,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Something went wrong",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please check your connection or try again.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                          hasErrorOccurred = false;
                        });
                        fetchVendors();
                      },
                      icon: const Icon(
                        LucideIcons.refreshCw,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: Text(
                        "Retry",
                        style: GoogleFonts.poppins(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        buildSearchBar(),
                        buildAddButton(),
                        const SizedBox(height: 12),
                        ...filteredVendors
                            .map((vendor) => buildVendorCard(vendor))
                            ,
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}
