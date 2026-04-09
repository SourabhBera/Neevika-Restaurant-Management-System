import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter/services.dart';

class VerifyPhoneNumberScreen extends StatefulWidget {
  const VerifyPhoneNumberScreen({super.key});

  @override
  State<VerifyPhoneNumberScreen> createState() => _VerifyPhoneNumberScreenState();
}

class _VerifyPhoneNumberScreenState extends State<VerifyPhoneNumberScreen> {
  List<TextEditingController> phoneControllers =
      List.generate(3, (_) => TextEditingController()); // default 3 fields
  List<bool> invalidFields = List.generate(3, (_) => false);
  bool isLoading = false;
  List<Map<String, dynamic>> customerResults = [];

  void addPhoneField() {
    setState(() {
      phoneControllers.add(TextEditingController());
      invalidFields.add(false);
    });
  }

  Future<void> submitPhones() async {
    // Validation — only non-empty fields are checked
    bool hasError = false;
    for (int i = 0; i < phoneControllers.length; i++) {
      final value = phoneControllers[i].text.trim();
      if (value.isNotEmpty && value.length != 10) {
        invalidFields[i] = true;
        hasError = true;
      } else {
        invalidFields[i] = false;
      }
    }
    setState(() {});

    // If all fields are empty, allow (per your requirement)
    if (phoneControllers.every((c) => c.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("All fields are empty — nothing to verify",
              style: GoogleFonts.poppins()),
        ),
      );
      return;
    }

    if (hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please enter valid 10-digit phone numbers",
              style: GoogleFonts.poppins()),
        ),
      );
      return;
    }

    final phoneNumbers =
        phoneControllers.map((c) => c.text.trim()).where((n) => n.isNotEmpty).toList();

    setState(() {
      isLoading = true;
      customerResults.clear();
    });

    try {
      final url = Uri.parse("${dotenv.env['API_URL']}/crm/QR/verify-phone");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phones": phoneNumbers}),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          customerResults = List<Map<String, dynamic>>.from(data);
        });
      } else if (response.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No user details found", style: GoogleFonts.poppins()),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Error: ${response.statusCode}",
                  style: GoogleFonts.poppins())),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e", style: GoogleFonts.poppins())),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  double getOfferValue(Map<String, dynamic> customer) {
    final offer = customer['offer'];
    if (offer == null) return 0;
    return (offer['offer_value'] ?? 0).toDouble();
  }

  Widget buildCustomerCard(Map<String, dynamic> customer, bool highlight) {
    final offer = customer['offer'];
    String offerValueText = '-';

    if (offer != null) {
      final value = offer['offer_value'];
      final type = offer['offer_type'];
      if (type == 'percent') {
        offerValueText = "$value%";
      } else if (type == 'cash') {
        offerValueText = "₹$value";
      } else {
        offerValueText = value?.toString() ?? '-';
      }
    }

    String createdAgo = customer['createdAgo'] ?? '-';
    bool isToday =
        createdAgo.contains("minutes") || createdAgo.contains("hours");

    return Card(
      color: highlight ? Colors.yellow[100] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: highlight
            ? BorderSide(color: Colors.orange, width: 2)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: highlight ? 4 : 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Name: ${customer['name'] ?? "No Name"}",
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text("Phone Number: ${customer['phone_number'] ?? '-'}",
                style: GoogleFonts.poppins(fontSize: 11)),
            Text("Email: ${customer['email'] ?? '-'}",
                style: GoogleFonts.poppins(fontSize: 11)),
            Text("Offer Value: $offerValueText",
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 16,
                    color: isToday ? Colors.green : Colors.red),
                const SizedBox(width: 6),
                Text(createdAgo,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isToday ? Colors.green : Colors.red,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in phoneControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // compute highest offer dynamically when building
    double highestOfferValue = customerResults.isEmpty
        ? 0
        : customerResults
            .map(getOfferValue)
            .reduce((a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text("Verify Phone Numbers",
            style: GoogleFonts.poppins(
                color: Colors.black87, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    ...List.generate(phoneControllers.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14.0),
                        child: TextField(
                          controller: phoneControllers[index],
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          style: GoogleFonts.poppins(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: "Enter phone number",
                            hintStyle:
                                GoogleFonts.poppins(color: Colors.grey[500]),
                            prefixIcon:
                                const Icon(Icons.phone, color: Colors.blue),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: invalidFields[index]
                                      ? Colors.red
                                      : Colors.transparent,
                                  width: 1),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: invalidFields[index]
                                      ? Colors.red
                                      : Colors.transparent,
                                  width: 1),
                            ),
                          ),
                        ),
                      );
                    }),
                    if (customerResults.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text("Results:",
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      ...customerResults.map((c) {
                        bool highlight =
                            getOfferValue(c) == highestOfferValue;
                        return buildCustomerCard(c, highlight);
                      }).toList(),
                    ],
                  ],
                ),
              ),
              isLoading
                  ? LoadingAnimationWidget.staggeredDotsWave(
                      color: Colors.blue, size: 40)
                  : Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: addPhoneField,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text("Add Number",
                                style: GoogleFonts.poppins(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.black87,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: submitPhones,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text("Submit",
                                style: GoogleFonts.poppins(fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
