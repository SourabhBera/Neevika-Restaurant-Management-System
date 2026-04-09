import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;
import 'package:Neevika/screens/Food/Inventory/EditPurchaseScreen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:Neevika/screens/Vendors/VendorEditScreen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:Neevika/utils/web_downloader_stub.dart'
    if (dart.library.html) 'package:Neevika/utils/web_downloader_web.dart';
import 'dart:typed_data';

extension StringCasingExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

class VendorDetailsScreen extends StatefulWidget {
  final dynamic vendor;
  final Map<String, dynamic> purchaseHistories;
  
  const VendorDetailsScreen({super.key, required this.vendor, required this.purchaseHistories,});
  
  @override
  State<VendorDetailsScreen> createState() => _VendorDetailsScreenState();
}

class _VendorDetailsScreenState extends State<VendorDetailsScreen> {
  String selectedDeliveryTab = 'Pending';
  List<String> categories = ['Pending', 'Complete'];
  String selectedCategory = 'Pending';
  File? _selectedImage;
  Map<String, dynamic>? vendorDetails;
  Map<String, dynamic>? purchaseHistories;
  Map<String, dynamic>? drinksPurchaseHistories;
  bool isLoading = true;

  Future<void> fetchVendorDetails() async {
  final id = widget.vendor['id']; // assuming this is available
  final url = Uri.parse('${dotenv.env['API_URL']}/vendor/$id');

  try {
    final response = await http.get(
      url,
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        vendorDetails = data['vendor'];
        purchaseHistories = data['purchaseHistories'];
        drinksPurchaseHistories = data['drinksPurchaseHistories']; // ← added
        isLoading = false;
      });
    } else {
      throw Exception('Failed to load vendor details');
    }
  } catch (e) {
    setState(() {
      isLoading = false;
    });
    print('Error: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error fetching vendor details')),
    );
  }
}



Future<void> downloadImage(BuildContext context, String imageUrl) async {
  try {
    final response = await http.get(Uri.parse(imageUrl));

    if (response.statusCode != 200) {
      throw Exception('Failed to download image. Status: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'downloaded_image_$timestamp.jpg';

    if (kIsWeb) {
      triggerWebDownload(bytes, fileName);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Image download triggered in browser.")),
      );
      return;
    }

    // Mobile (Android/iOS)
    bool hasPermission = true;

    if (io.Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt <= 32) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          hasPermission = result.isGranted;
        }
      }
    }

    if (!hasPermission) {
      throw Exception('Storage permission not granted');
    }

    final dir = io.Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory(); // iOS

    final downloadsDir = io.Directory("${dir!.path}/downloads");

    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }

    final filePath = '${downloadsDir.path}/$fileName';
    final file = io.File(filePath);
    await file.writeAsBytes(bytes);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Image downloaded to: $filePath")),
    );

    OpenFile.open(filePath);
  } catch (e) {
    print("Error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Download failed: $e")),
    );
  }
}

@override
void initState() {
  super.initState();
  fetchVendorDetails();
}


  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image selection cancelled or failed.')),
      );
    }
  }

  Future<void> _uploadImage() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }

    final uri = Uri.parse("https://your-api-url.com/api/upload");
    final request = http.MultipartRequest('POST', uri);

    request.files.add(await http.MultipartFile.fromPath('file', _selectedImage!.path));
    request.fields['vendorId'] = widget.vendor['id'].toString();
    request.headers['Authorization'] = 'Bearer your_token_here';

    final response = await request.send();

    if (response.statusCode == 200) {
      setState(() {
        _selectedImage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image uploaded successfully!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload failed.')),
      );
    }
  }




Widget buildDeliveryCard({
  required BuildContext context,
  required String title,
  required String status,
  required String date,
  required String amount,
  required Color statusColor,
  required Color statusBackground,
  required bool showUpload,
  required File? selectedImage,
  required VoidCallback pickImage,
  required VoidCallback uploadImage,
  required bool isCompleteTab,
  Widget? child,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFE5E5E5)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header inside the card
        Text(
          status == 'Pending' ? "Pending Deliveries" : "Completed Deliveries",
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1C1917),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status == 'Pending'
              ? "Deliveries awaiting receipt upload, approval, or payment"
              : "Deliveries that have been approved and completed",
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: const Color(0xFF78726D),
          ),
        ),
        const SizedBox(height: 24),

        // Delivery Content Box
        child ??
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E5E5)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Date
              Text(
                date,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF78726D),
                ),
              ),

              const SizedBox(height: 12),

              // Amount
              Text(
                "\₹$amount",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1C1917),
                ),
              ),

              const SizedBox(height: 12),

              // Conditional Button Logic
              if (showUpload) ...[
                if (selectedImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      selectedImage,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: uploadImage,
                    icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(
                      "Submit Receipt",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.green,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: pickImage,
                    icon: const Icon(Icons.upload, size: 18),
                    label: Text(
                      "Upload Receipt1",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      foregroundColor: const Color(0xFF1C1917),
                      backgroundColor: const Color(0xFFF8F5F2),
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFFE5E5E5)),
                      ),
                    ),
                  ),
                ],
              ] else if (status.toLowerCase() == 'completed') ...[
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Downloading receipt...')),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: Text(
                    "Download Receipt",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    foregroundColor: const Color(0xFF1C1917),
                                    backgroundColor: const Color(0xFFF8F5F2),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFE5E5E5)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildSwitchButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEDEBE9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children:
              categories.map((category) {
                bool isSelected = selectedCategory == category;

                IconData? icon;
                if (category.toLowerCase() == 'pending') {
                  icon = LucideIcons.clock;
                } else if (category.toLowerCase() == 'complete') {
                  icon = LucideIcons.checkCheck;
                }
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedCategory = category;
                      selectedDeliveryTab =
                          category == 'Pending' ? 'Pending' : 'Completed';
                    });
                  },
                  child: AnimatedScale(
                    scale: isSelected ? 1.1 : 1.0, // Add scale animation
                    duration: const Duration(
                      milliseconds: 250,
                    ), // Smooth scale transition
                    curve: Curves.easeInOut,
                    child: AnimatedContainer(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 36,
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? const Color(0xFFFCFAF8)
                                : const Color(0xFFEDEBE9),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow:
                            isSelected
                                ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                                : [],
                      ),
                      duration: const Duration(
                        milliseconds: 200,
                      ), // Smooth background color transition
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 16,
                            color:
                                isSelected
                                    ? const Color(0xFF1C1917)
                                    : const Color(0xFF78726D),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            category,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color:
                                  isSelected
                                      ? const Color(0xFF1C1917)
                                      : const Color(0xFF78726D),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

    Widget buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF78726D),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: const Color(0xFF1C1917),
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }


void showPurchaseDetailsPopup(
  BuildContext context,
  List<dynamic> items,
  String title,
  String supplierName,
  DateTime purchaseDate,
  String deliveryStatus,
  String paymentStatus,
  String paymentMethod,
  String totalCost,
  String? imagePath,
) {
  print('\n\n $imagePath');
  print('\n\n ${dotenv.env['API_URL_1']}$imagePath');
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Purchase Details',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Purchase from $supplierName on ${DateFormat('dd MMM yyyy').format(purchaseDate)}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: const Color(0xFF78726D),
                ),
              ),
              const SizedBox(height: 16),

              // Title and other purchase details
              Text(
                "Title: $title",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: const Color(0xFF1C1917),
                ),
              ),
              const SizedBox(height: 16),

              // Items Table
              Text(
                "Items:",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: const Color(0xFF1C1917),
                ),
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.5),
                    1: FlexColumnWidth(1.2),
                    
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: Color(0xFFE5E5E5),
                      width: 1,
                    ),
                  ),
                  children: items.map<TableRow>((item) {
                    return tableRow(
                      item['name'] ?? 'Unknown Item',
                      "${item['qty']} ${item['unit']} ",
                     
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Total Cost and other details
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Total:",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      totalCost.toString(),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Delivery Status:",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      deliveryStatus,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Payment Status and Payment Method
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Payment Status:",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      paymentStatus,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Payment Method:",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: const Color(0xFF1C1917),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(
                      paymentMethod,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Receipt Image with Download Icon
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    // Image Widget
                    imagePath != null
                        ? Center(
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                'http://13.60.15.89:3000$imagePath',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) => Center(
                                  child: Text("Failed to load image", style: GoogleFonts.poppins(fontSize: 12)),
                                ),
                              ),
                            ),
                        )
                        : Center(
                            child: Text(
                              "No Receipt Uploaded",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: const Color(0xFF78726D),
                              ),
                            ),
                          ),

                    // Download Icon
                    if (imagePath != null)
                      Positioned(
                        right: 05,
                        bottom: 05,
                        child: GestureDetector(
                          onTap: () {
                            downloadImage(context, 'http://13.60.15.89:3000$imagePath');
                          },
                          child: CircleAvatar(
                            backgroundColor: Colors.blue,
                            radius: 10,
                            child: Icon(
                              Icons.download,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF89F3F),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    "Close",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}



  // Table row helper
  TableRow tableRow(String item, String quantity,) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(item, style: GoogleFonts.poppins(fontSize: 14)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(quantity, style: GoogleFonts.poppins(fontSize: 14)),
        ),
        
      ],
    );
  }


double calculateTotalCost(List<dynamic> items) {
  double total = 0.0;

  for (var item in items) {
    double qty = double.tryParse(item['qty'].toString()) ?? 0.0;
    double price = double.tryParse(item['price'].toString()) ?? 0.0;
    total += qty * price;
  }

  return total;
}


 @override
  Widget build(BuildContext context) {
  // Extract pending and complete deliveries safely
  final pendingGeneral = purchaseHistories?['pending'] as List<dynamic>? ?? [];
  final completeGeneral = purchaseHistories?['complete'] as List<dynamic>? ?? [];

  final pendingDrinks = drinksPurchaseHistories?['pending'] as List<dynamic>? ?? [];
  final completeDrinks = drinksPurchaseHistories?['complete'] as List<dynamic>? ?? [];

  final pendingDeliveries = [...pendingGeneral, ...pendingDrinks];
  final completeDeliveries = [...completeGeneral, ...completeDrinks];

  // Pick deliveries to show based on selectedCategory
  final selected = selectedCategory.toLowerCase();
  final deliveries = selected == 'pending' ? pendingDeliveries : completeDeliveries;


    print('Selected category: $selectedCategory');
    print('Pending count: ${pendingDeliveries.length}');
    print('Complete count: ${completeDeliveries.length}');
    print('Deliveries selected: ${deliveries.length}');
  return Scaffold(
    backgroundColor: const Color(0xFFF8F5F2),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF8F5F2),
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.vendor['name']?.toString() ?? 'Vendor Name',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.vendor['business_type']?.toString() ?? 'Business Type',
            style: GoogleFonts.poppins(fontSize: 10, color: Colors.black54),
          ),
        ],
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.97,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Buttons: Edit Vendor and New Delivery
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EditVendorScreen(vendor: widget.vendor),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.edit, color: Color(0xFF1C1917)),
                      label: Text(
                        "Edit Vendor",
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF1C1917),
                          fontWeight: FontWeight.w500,
                          fontSize: 10.5
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFF8F5F2),
                        side: const BorderSide(color: Color(0xFFDCDCDC)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/add_purchase');
                      },
                      icon: const Icon(LucideIcons.truck, color: Colors.white),
                      label: Text(
                        "New Delivery",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 10.5
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD95326),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Vendor Info Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vendor Information',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (widget.vendor['status']?.toString() ?? 'unknown').capitalize(),
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        buildInfoRow('Contact Person', widget.vendor['contact_person'] ?? 'N/A'),
                        buildInfoRow('Email', widget.vendor['email'] ?? 'N/A'),
                        buildInfoRow('Phone', widget.vendor['phone'] ?? 'N/A'),
                        buildInfoRow('Address', widget.vendor['address'] ?? 'N/A'),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Switch Button to toggle between Pending & Complete deliveries
              _buildSwitchButton(),

              const SizedBox(height: 24),

              // Outer container for deliveries
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE5E5E5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$selectedCategory Deliveries',
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selectedCategory == 'Pending'
                          ? 'Deliveries awaiting receipt upload, approval or payment.'
                          : 'Deliveries that have been approved & completed.',
                      style: GoogleFonts.poppins(
                        fontSize: 11.7,
                        color: const Color(0xFF78726D),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // If no deliveries, show a message inside outer container
                    if (deliveries.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE5E5E5)),
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0xFFF8F5F2),
                        ),
                        child: Text(
                          "No ${selectedCategory.toLowerCase()} deliveries found.",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF78726D),
                          ),
                        ),
                      )
                    else
                      // Otherwise, list delivery cards
                      Column(
                        children: deliveries.map<Widget>((delivery) {
                          print('\n\n\n------$delivery');
                          final isPending = delivery['delivery_status'] == 'pending';
                          final isCompleted = delivery['delivery_status'] == 'completed';
                          final receiptUploaded = delivery['receipt_image'] != null;

                          final rawDate = delivery['date'];
                          String formattedDate = '';

                          if (rawDate != null) {
                            try {
                              final parsedDate = DateTime.parse(rawDate);
                              formattedDate = DateFormat('d MMMM, yyyy').format(parsedDate);
                            } catch (e) {
                              formattedDate = rawDate.toString(); // fallback
                            }
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: GestureDetector(
                              onTap: () {
                                final items = delivery['items'] ?? [];
                                final title = delivery['title'] ?? '';
                                final supplierName = widget.vendor['name'] ?? '';
                                final purchaseDate = DateTime.tryParse(delivery['date']) ?? DateTime.now();
                                final deliveryStatus = delivery['delivery_status'] ?? '';
                                final paymentStatus = delivery['payment_status'] ?? '';
                                final paymentMethod = delivery['payment_type'] ?? '';
                                final totalCost = delivery['amount'] ?? '0';
                                final imagePath = delivery['receipt_image']; // ← Add this
                                  

                                showPurchaseDetailsPopup(
                                  context,
                                  items,
                                  title,
                                  supplierName,
                                  purchaseDate,
                                  deliveryStatus,
                                  paymentStatus,
                                  paymentMethod,
                                  totalCost,
                                  imagePath,
                                );
                              },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFE5E5E5)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Title & Status row
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          delivery['title'] ?? 'Untitled',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12.7,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF1C1917),
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isPending
                                              ? Colors.orange.shade100
                                              : Colors.green.shade100,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          (delivery['delivery_status']?.toString() ?? 'Unknown').capitalize(),
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: isPending ? Colors.orange : Colors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 6),

                                  // Date row
                                  Text(
                                    formattedDate,
                                    style: GoogleFonts.poppins(
                                      fontSize: 11.2,
                                      color: const Color(0xFF78726D),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Amount row
                                  Text(
                                    "\₹${delivery['amount'] ?? '0.00'}",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1C1917),
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Receipt upload / download button logic
                                  if (isPending && !receiptUploaded)
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EditPurchasePage(
                                              purchaseData: delivery, // 👈 Pass the data here
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.upload, size: 18),
                                      label: Text(
                                        "Edit Purchase",
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        foregroundColor: const Color(0xFF1C1917),
                                        backgroundColor: const Color(0xFFF8F5F2),
                                        minimumSize: const Size(double.infinity, 48),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: const BorderSide(color: Color(0xFFE5E5E5)),
                                        ),
                                      ),
                                    )
                                  else if (isCompleted)
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Downloading receipt...')),
                                        );
                                      },
                                      icon: const Icon(Icons.download),
                                      label: Text(
                                        "Download Receipt",
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        elevation: 0,
                                        foregroundColor: const Color(0xFF1C1917),
                                        backgroundColor: const Color(0xFFF8F5F2),
                                        minimumSize: const Size(double.infinity, 48),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: const BorderSide(color: Color(0xFFE5E5E5)),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                          );
                        }).toList(),
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
}


}
