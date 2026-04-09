import 'dart:convert';
import 'dart:io';
import 'package:Neevika/screens/Food/Inventory/EditPurchaseScreen.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  _PurchaseScreenState createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  List<dynamic> purchaseHistory = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;

  DateTime? startDate;
  DateTime? endDate;
  String approvalFilter = 'All';
  String searchQuery = '';
  int currentPage = 1;

  @override
  void initState() {
    super.initState();
    fetchPurchases(reset: true);
  }

  Future<void> fetchPurchases({bool reset = false}) async {
    try {
      if (reset) {
        setState(() {
          isLoading = true;
          currentPage = 1;
          hasMore = true;
          purchaseHistory.clear();
        });
      } else {
        setState(() => isLoadingMore = true);
      }

      final queryParams = {
        'page': currentPage.toString(),
        'limit': '15',
        if (startDate != null)
          'startDate': DateFormat("yyyy-MM-dd'T'00:00:00.000'Z'").format(startDate!.toUtc()),
        if (endDate != null)
          'endDate': DateFormat("yyyy-MM-dd'T'23:59:59.999'Z'").format(endDate!.toUtc()),
        if (approvalFilter == 'Approved') 'approved': 'true',
        if (approvalFilter == 'Pending') 'approved': 'false',
        if (searchQuery.isNotEmpty) 'vendorName': searchQuery,
      };

      final uri = Uri.parse('${dotenv.env['API_URL']}/purchaseHistory')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> newItems = data['data'] ?? [];

        setState(() {
          if (reset) {
            purchaseHistory = newItems;
          } else {
            purchaseHistory.addAll(newItems);
          }

          isLoading = false;
          isLoadingMore = false;
          hasMore = currentPage < (data['totalPages'] ?? 1);
        });
      } else {
        throw Exception('Failed to load purchase history');
      }
    } catch (e) {
      print('Error fetching data: $e');
      setState(() {
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  Future<void> selectStartDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: startDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => startDate = picked);
      fetchPurchases(reset: true);
    }
  }

  Future<void> selectEndDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: endDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => endDate = picked);
      fetchPurchases(reset: true);
    }
  }

  Future<void> downloadImage(BuildContext context, String imageUrl) async {
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      bool hasPermission = true;

      if (sdkInt <= 32) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          final result = await Permission.storage.request();
          hasPermission = result.isGranted;
        }
      }

      if (!hasPermission) throw Exception('Storage permission not granted');

      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final dir = await getExternalStorageDirectory();
        final downloadsDir = Directory("${dir!.path}/downloads");
        if (!downloadsDir.existsSync()) downloadsDir.createSync(recursive: true);
        final filePath =
            '${downloadsDir.path}/downloaded_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(bytes);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Image downloaded to: $filePath")),
        );
        OpenFile.open(filePath);
      } else {
        throw Exception('Failed to download image');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download failed: $e")),
      );
    }
  }

  void loadMore() {
    if (!isLoadingMore && hasMore) {
      setState(() => currentPage++);
      fetchPurchases();
    }
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
            const SizedBox(height: 2),
            Text('Purchase History',
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text('Manage and view all purchases',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : buildFilterLayout(context),
    );
  }

  Widget buildFilterLayout(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: selectStartDate,
                      child: _dateBox(
                        startDate == null
                            ? 'Start Date'
                            : DateFormat('dd MMM yyyy').format(startDate!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: selectEndDate,
                      child: _dateBox(
                        endDate == null
                            ? 'End Date'
                            : DateFormat('dd MMM yyyy').format(endDate!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: approvalFilter,
                      items: ['All', 'Approved', 'Pending']
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e,
                                    style: GoogleFonts.poppins(fontSize: 12)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() => approvalFilter = val!);
                        fetchPurchases(reset: true);
                      },
                      decoration: _inputDecoration(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      onChanged: (val) {
                        searchQuery = val;
                        fetchPurchases(reset: true);
                      },
                      decoration: _inputDecoration(
                        hint: 'Search by Vendor',
                        icon: const Icon(Icons.search, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: purchaseHistory.isEmpty
              ? const Center(child: Text('No purchases found'))
              : buildPurchaseList(context),
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: ElevatedButton(
              onPressed: loadMore,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C1917),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: isLoadingMore
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text('Load More',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontWeight: FontWeight.w500)),
            ),
          ),
      ],
    );
  }

  Widget buildPurchaseList(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ListView.builder(
        itemCount: purchaseHistory.length,
        itemBuilder: (context, index) {
          final purchaseData = purchaseHistory[index];
          DateTime purchaseDate =
              DateTime.tryParse(purchaseData['createdAt']) ?? DateTime.now();
          double totalCost =
              double.tryParse(purchaseData['amount'].toString()) ?? 0.0;
          String title = purchaseData['title'] ?? 'N/A';
          String supplierName = purchaseData['vendor']?['name'] ?? 'Unknown Vendor';
          bool approved = purchaseData['approved'] == true;
          List<dynamic> items = purchaseData['items'] ?? [];
          String? imagePath = purchaseData['receipt_image'];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E5E5)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date + Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('dd MMM yyyy').format(purchaseDate),
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              approved ? Colors.green.shade200 : Colors.orange.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          approved ? "Approved" : "Pending",
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF4A4A4A))),
                  Text(supplierName,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: const Color(0xFF78726D))),
                  const SizedBox(height: 12),
                  Text("Items:",
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1C1917))),
                  const SizedBox(height: 6),
                  ...items.take(2).map<Widget>((item) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item['name'] ?? 'Unknown Item',
                            style: GoogleFonts.poppins(fontSize: 12)),
                        Text("${item['qty']} ${item['unit']}",
                            style: GoogleFonts.poppins(fontSize: 12)),
                      ],
                    );
                  }),
                  if (items.length > 2)
                    Text("+ ${items.length - 2} more items",
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),

                  // View Details button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        showPurchaseDetailsPopup(
                          context,
                          items,
                          title,
                          supplierName,
                          purchaseDate,
                          approved,
                          totalCost,
                          imagePath,
                          purchaseData['id'],
                          purchaseData['type'], // ✅ pass type here
                          purchaseData, // pass entire purchase data
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
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


Future<void> approvePurchase(
  BuildContext context,
  int purchaseId,
  void Function(void Function()) setDialogState,
  String type,
) async {
  try {
    final uri = Uri.parse('${dotenv.env['API_URL']}/purchaseHistory/$purchaseId/complete');

    final response = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"type": type}), // ✅ Send type in body
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase approved successfully!')),
      );
      Navigator.of(context).pop();
      fetchPurchases(reset: true);
    } else {
      throw Exception('Approval failed');
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}


  // Popup table row
  TableRow tableRow(String name, String qty, ) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(name,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400)),
      ),
      Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(qty,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w400)),
      ),
      
    ]);
  }


void showEditItemsDialog(BuildContext context, List<dynamic> items, int purchaseId, void Function(void Function()) setDialogState) {
  List<Map<String, dynamic>> editableItems = List<Map<String, dynamic>>.from(items);

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setEditState) {
          return AlertDialog(
            title: Text("Edit Items", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  ...editableItems.asMap().entries.map((entry) {
                    int index = entry.key;
                    var item = entry.value;
                    return Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: item['name'],
                            onChanged: (val) => editableItems[index]['name'] = val,
                            decoration: InputDecoration(
                              labelText: 'Item Name',
                              labelStyle: GoogleFonts.poppins(fontSize: 11),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextFormField(
                            initialValue: item['qty'].toString(),
                            onChanged: (val) => editableItems[index]['qty'] = double.tryParse(val) ?? 0,
                            decoration: InputDecoration(
                              labelText: 'Qty',
                              labelStyle: GoogleFonts.poppins(fontSize: 11),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextFormField(
                            initialValue: item['unit'],
                            onChanged: (val) => editableItems[index]['unit'] = val,
                            decoration: InputDecoration(
                              labelText: 'Unit',
                              labelStyle: GoogleFonts.poppins(fontSize: 11),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                          onPressed: () {
                            setEditState(() {
                              editableItems.removeAt(index);
                            });
                          },
                        )
                      ],
                    );
                  }),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setEditState(() {
                          editableItems.add({'name': '', 'qty': 0, 'unit': ''});
                        });
                      },
                      icon: const Icon(Icons.add, size: 18, color: Colors.green),
                      label: Text("Add Item", style: GoogleFonts.poppins(color: Colors.green, fontSize: 12)),
                    ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel", style: GoogleFonts.poppins(fontSize: 12)),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final uri = Uri.parse('${dotenv.env['API_URL']}/purchaseHistory/$purchaseId/updateItems');
                    final response = await http.put(
                      uri,
                      headers: {"Content-Type": "application/json"},
                      body: jsonEncode({"items": editableItems}),
                    );

                    if (response.statusCode == 200) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Items updated successfully")),
                      );
                      Navigator.pop(context);
                      setDialogState(() {
                        items.clear();
                        items.addAll(editableItems);
                      });
                      fetchPurchases(reset: true);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed to update items: ${response.body}")),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: Text("Save Changes", style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
              )
            ],
          );
        },
      );
    },
  );
}



void showPurchaseDetailsPopup(
     BuildContext context,
     List<dynamic> items,
     String title,
     String supplierName,
     DateTime purchaseDate,
     bool approved,
     double totalCost,
     String? imagePath,
     int purchaseId,
     String type,
     Map<String, dynamic> purchaseData, // Add this
   )
 {
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Purchase Details',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: const Color(0xFF1C1917),
                        ),
                      ),
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
                    Text(
                      "Title: $title",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: const Color(0xFF1C1917),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(1),
                          
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
                            "${item['qty']} ${item['unit']}",
                            
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    rowText("Total:", "₹$totalCost"),
                    rowText(
                        "Approval Status:", approved ? "Approved" : "Pending"),
                    const SizedBox(height: 16),
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D9D9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          imagePath != null
                              ? Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      'http://13.60.15.89:3000$imagePath',
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Center(
                                        child: Text("Failed to load image",
                                            style:
                                                GoogleFonts.poppins(fontSize: 12)),
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
                          if (imagePath != null)
                            Positioned(
                              right: 5,
                              bottom: 5,
                              child: GestureDetector(
                                onTap: () {
                                  downloadImage(
                                      context, 'http://13.60.15.89:3000$imagePath');
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
                    if (!approved)
  SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: () async {
        // Close the current dialog first
        Navigator.of(context).pop();
        
        // Navigate to edit page with purchase data
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditPurchasePage(
              purchaseData: {
                'id': purchaseId,
                'title': title,
                'amount': totalCost,
                'date': purchaseDate.toIso8601String(),
                'vendor_id': purchaseData['vendor']?['id'],
                'notes': purchaseData['notes'] ?? '',
                'delivery_status': purchaseData['delivery_status'] ?? 'pending',
                'payment_status': purchaseData['payment_status'] ?? 'pending',
                'payment_type': purchaseData['payment_type'] ?? 'N/A',
                'items': items,
                'receipt_image': imagePath,
              },
            ),
          ),
        );
        
        // Refresh the purchase list if edit was successful
        if (result == true) {
          fetchPurchases(reset: true);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF007BFF),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        "Edit Purchase",
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: Colors.white,
        ),
      ),
    ),
  ),
                    const SizedBox(height: 10),

                    if (!approved)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            await approvePurchase(context, purchaseId, setDialogState, type);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            "Approve Purchase",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
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
        ),
      );
    },
  );
}


  Widget rowText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: const Color(0xFF1C1917),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: const Color(0xFF1C1917),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint, Widget? icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(fontSize: 12),
      prefixIcon: icon,
      contentPadding:
          const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _dateBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E5E5)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 12)),
    );
  }
}
