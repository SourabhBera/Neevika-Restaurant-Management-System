import 'dart:typed_data';
import 'dart:io' show File; // ✅ Only imported on mobile
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AddIncidentPage extends StatefulWidget {
  const AddIncidentPage({super.key});

  @override
  State<AddIncidentPage> createState() => _AddIncidentPageState();
}

class _AddIncidentPageState extends State<AddIncidentPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime selectedDate = DateTime.now();

  // ✅ Different lists for web and mobile
  List<File> _mobileImages = [];
  List<Uint8List> _webImages = [];

  final String baseUrl = "${dotenv.env['API_URL']}/incident-report/";

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();

    if (picked.isNotEmpty) {
      setState(() async {
       if (kIsWeb) {
          final futures = picked.map((p) => p.readAsBytes()).toList();
          final results = await Future.wait(futures);
          setState(() {
            _webImages = results;
          });
        } else {
          setState(() {
            _mobileImages = picked.map((p) => File(p.path)).toList();
          });
        }

      });
    }
  }

  Future<void> _submitCreate() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');

    if (token == null) {
      print('No token found. User might not be logged in.');
      return;
    }

    final decodedToken = JwtDecoder.decode(token);
    final userId = decodedToken['id'];

    final uri = Uri.parse(baseUrl);
    final request = http.MultipartRequest('POST', uri);

    request.fields['title'] = _titleController.text;
    request.fields['description'] = _descriptionController.text;
    request.fields['incidentDate'] = selectedDate.toIso8601String();
    request.fields['userId'] = userId.toString();

    // ✅ Handle Web and Mobile differently
    if (kIsWeb) {
      for (int i = 0; i < _webImages.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
          'images',
          _webImages[i],
          filename: 'incident_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
        ));
      }
    } else {
      for (var image in _mobileImages) {
        final stream = http.ByteStream(image.openRead());
        final length = await image.length();
        final multipartFile = http.MultipartFile(
          'images',
          stream,
          length,
          filename: image.path.split('/').last,
        );
        request.files.add(multipartFile);
      }
    }

    try {
      final response = await request.send();
      final res = await http.Response.fromStream(response);

      if (res.statusCode == 201) {
        if (context.mounted) Navigator.pop(context, true);
      } else {
        print("Create failed: ${res.statusCode}, ${res.body}");
      }
    } catch (e) {
      print("Error creating incident: $e");
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Add Incident Report", style: GoogleFonts.poppins()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildTextField("Title", _titleController),
              _buildTextField("Description", _descriptionController, maxLines: 3),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    "Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}",
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.calendar_month),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _buildImagePreview(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _submitCreate,
                  child: Text("Add Incident", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ Works for Web (Uint8List) and Mobile (File)
  Widget _buildImagePreview() {
    final hasImages = kIsWeb ? _webImages.isNotEmpty : _mobileImages.isNotEmpty;

    if (!hasImages) {
      return Center(
        child: Text(
          "Tap to upload images",
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: kIsWeb ? _webImages.length : _mobileImages.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: kIsWeb
              ? Image.memory(_webImages[index], fit: BoxFit.cover, width: 120)
              : Image.file(_mobileImages[index], fit: BoxFit.cover, width: 120),
        );
      },
    );
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: GoogleFonts.poppins(),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        validator: (val) => val == null || val.isEmpty ? 'Required' : null,
      ),
    );
  }
}
