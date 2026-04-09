import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class MyInformationScreen extends StatefulWidget {
  final String userId;
  const MyInformationScreen({super.key, required this.userId});

  @override
  State<MyInformationScreen> createState() => _MyInformationScreenState();
}

class _MyInformationScreenState extends State<MyInformationScreen> {
  bool isLoading = true;
  bool isError = false;
  bool isEditing = false;
  Map<String, dynamic>? userData;

  late TextEditingController emailController;
  late TextEditingController phoneController;
  late TextEditingController addressController;
  late TextEditingController usernameController;

  @override
  void initState() {
    super.initState();
    fetchUserInfo();
  }

  Future<void> fetchUserInfo() async {
    final url = Uri.parse('${dotenv.env['API_URL']}/auth/user_details/${widget.userId}');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          userData = data;
          usernameController = TextEditingController(text: data['name'] ?? '');
          emailController = TextEditingController(text: data['email'] ?? '');
          phoneController = TextEditingController(text: data['phone_number'] ?? '');
          addressController = TextEditingController(text: data['address'] ?? '');
          isLoading = false;
        });
      } else {
        throw Exception('Failed to load user data');
      }
    } catch (e) {
      print('Error fetching user info: $e');
      setState(() {
        isError = true;
        isLoading = false;
      });
    }
  }

  void _download(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;

    final baseUrl = dotenv.env['API_URL'];
    final fullUrl = '$baseUrl$relativePath'; // Combine base and relative path
    final uri = Uri.parse(fullUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link')),
      );
    }
  }


  Future<void> _uploadAadharCard(int userId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final uri = Uri.parse('${dotenv.env['API_URL']}/admin/aadharCard/$userId');
      final request = http.MultipartRequest('PUT', uri);
      request.files.add(await http.MultipartFile.fromPath('pdf_file', file.path!));

      try {
        final response = await request.send();
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aadhar Card uploaded successfully')),
          );
          await fetchUserInfo(); // Refresh data
        } else {
          final responseBody = await response.stream.bytesToString();
          debugPrint('Upload failed: $responseBody');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload Aadhar Card')),
          );
        }
      } catch (e) {
        debugPrint('Upload exception: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload error')),
        );
      }
    }
  }

  Future<void> _uploadPanCard(int userId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final uri = Uri.parse('${dotenv.env['API_URL']}/admin/panCard/$userId');
      final request = http.MultipartRequest('PUT', uri);
      request.files.add(await http.MultipartFile.fromPath('pdf_file', file.path!));

      try {
        final response = await request.send();
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PAN Card uploaded successfully')),
          );
          await fetchUserInfo(); // Refresh data
        } else {
          final responseBody = await response.stream.bytesToString();
          debugPrint('Upload failed: $responseBody');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload Pan Card')),
          );
        }
      } catch (e) {
        debugPrint('Upload exception: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload error')),
        );
      }
    }
  }


  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F5F2),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          'My Information',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : isError
              ? Center(
                  child: Text(
                    'Failed to load user info.',
                    style: GoogleFonts.poppins(fontSize: 16),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      // Profile Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Initials
                            Container(
                              width: 70,
                              height: 70,
                              decoration: const BoxDecoration(
                                color: Color(0xFF7B61FF),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  _getInitials(userData!['name']),
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  userData!['name'] ?? '',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      isEditing = true;
                                    });
                                  },
                                  child: const Icon(Icons.edit, size: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            isEditing
                                ? Column(
                                    children: [
                                      EditableField(controller: usernameController, label: 'Username'),
                                      const SizedBox(height: 10),
                                      EditableField(controller: emailController, label: 'Email'),
                                      const SizedBox(height: 10),
                                      EditableField(controller: phoneController, label: 'Phone'),
                                      const SizedBox(height: 10),
                                      EditableField(
                                          controller: addressController,
                                          label: 'Address',
                                          isMultiline: true),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  isEditing = false;
                                                  userData!['email'] = emailController.text;
                                                  userData!['phone_number'] = phoneController.text;
                                                  userData!['address'] = addressController.text;
                                                });
                                              },
                                              child: const Text('Cancel'),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () async {
                                                final url = Uri.parse('${dotenv.env['API_URL']}/admin/users/${widget.userId}');
                                                final updatedData = {
                                                  "name": usernameController.text,
                                                  "email": emailController.text,
                                                  "phone_number": phoneController.text,
                                                  "address": addressController.text,
                                                };

                                                try {
                                                  final response = await http.put(
                                                    url,
                                                    headers: {'Content-Type': 'application/json'},
                                                    body: json.encode(updatedData),
                                                  );

                                                  if (response.statusCode == 200) {
                                                    setState(() {
                                                      userData!['username'] = usernameController.text;
                                                      userData!['email'] = emailController.text;
                                                      userData!['phone_number'] = phoneController.text;
                                                      userData!['address'] = addressController.text;
                                                      isEditing = false;
                                                    });
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text("User info updated successfully")),
                                                    );
                                                  } else {
                                                    throw Exception("Failed to update");
                                                  }
                                                } catch (e) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text("Error updating user: $e")),
                                                  );
                                                }
                                              },
                                              child: const Text('Save'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      InfoField(label: 'Email', value: userData!['email'] ?? ''),
                                      const SizedBox(height: 10),
                                      InfoField(label: 'Phone', value: userData!['phone_number'] ?? ''),
                                      const SizedBox(height: 10),
                                      InfoField(
                                          label: 'Address',
                                          value: userData!['address'] ?? '',
                                          isMultiline: true),
                                    ],
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      // Documents Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.file_copy_outlined,
                                    color: Color(0xFF7B61FF), size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Documents',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            DocumentCard(
                              title: 'Aadhar Card',
                              id: userData!['aadhar_card_path'] ?? '',
                              userId: int.parse(widget.userId),
                              onUpload: _uploadAadharCard,
                              onDownload: _download,
                            ),

                            DocumentCard(
                              title: 'PAN Card',
                              id: userData!['pan_card_path'] ?? '',
                              userId: int.parse(widget.userId),
                              onUpload: _uploadPanCard,
                              onDownload: _download,
                            ),

                            DocumentCard(
                              title: 'Appointment Letter',
                              id: userData!['appointment_letter_path'] != null ? 'Available' : 'Not uploaded',
                              userId: int.parse(widget.userId),
                              downloadUrl: userData!['appointment_letter_path'],
                              onUpload: _uploadPanCard,
                              onDownload: _download,
                            ),

                            DocumentCard(
                              title: 'Resignation Letter',
                              id: userData!['leave_letter_path'] != null ? 'Available' : 'Not uploaded',
                              userId: int.parse(widget.userId),
                              downloadUrl: userData!['leave_letter_path'],
                              onUpload: _uploadPanCard,
                              onDownload: _download,
                            ),

                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  String _getInitials(String name) {
    List<String> parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty) {
      return parts[0][0].toUpperCase();
    } else {
      return '';
    }
  }
}

// EditableField Widget
class EditableField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isMultiline;

  const EditableField({
    super.key,
    required this.controller,
    required this.label,
    this.isMultiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: isMultiline ? 4 : 1,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF0F0F0),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          style: GoogleFonts.poppins(
            fontSize: 13.5,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

// InfoField Widget (Read-only)
class InfoField extends StatelessWidget {
  final String label;
  final String value;
  final bool isMultiline;

  const InfoField({
    super.key,
    required this.label,
    required this.value,
    this.isMultiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              color: Colors.black87,
            ),
            softWrap: isMultiline,
          ),
        ),
      ],
    );
  }
}

// DocumentCard Widget
class DocumentCard extends StatelessWidget {
  final String title;
  final String id; // Display value or document number
  final String? downloadUrl;
  final int userId;
  final void Function(int userId) onUpload;
  final void Function(String url) onDownload;

  const DocumentCard({
    super.key,
    required this.title,
    required this.id,
    this.downloadUrl,
    required this.userId,
    required this.onUpload,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isUploadType = title == 'Aadhar Card' || title == 'PAN Card';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAEAEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
              fontSize: 14.2,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            id.isNotEmpty ? id : 'Not uploaded',
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: Colors.black54,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: () {
                if (isUploadType) {
                  onUpload(userId);
                } else if (downloadUrl != null && downloadUrl!.isNotEmpty) {
                  onDownload(downloadUrl!);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No file available to download')),
                  );
                }
              },
              icon: Icon(
                isUploadType ? Icons.upload_file : Icons.download_outlined,
                size: 16,
                color: const Color(0xFF7B61FF),
              ),
              label: Text(
                isUploadType ? 'Upload' : 'Download',
                style: GoogleFonts.poppins(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF7B61FF),
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF7B61FF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
