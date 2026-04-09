import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AddDrinksPurchasePage extends StatefulWidget {
  const AddDrinksPurchasePage({super.key});

  @override
  _AddDrinksPurchasePageState createState() => _AddDrinksPurchasePageState();
}

class _AddDrinksPurchasePageState extends State<AddDrinksPurchasePage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _totalAmountController = TextEditingController(text: '0');
  final TextEditingController _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  XFile? _selectedImage;
  List<dynamic> categories = [];
  List<Map<String, dynamic>> items = [];
  List<dynamic> vendors = [];
  String? _selectedVendor;
  List<String> bottleSizes = ['180', '330', '660', '750'];
  PlatformFile? _excelFile;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _totalAmountController.dispose();
    _notesController.dispose();
    for (var item in items) {
      item["nameController"]?.dispose();
      item["qtyController"]?.dispose();
      item["priceController"]?.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchVendors();
    _fetchCategories();
  }

  Future<void> _fetchVendors() async {
    final url = Uri.parse('${dotenv.env['API_URL']}/vendor');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          vendors = json.decode(response.body);
        });
      } else {
        throw Exception('Failed to load vendors');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _fetchCategories() async {
    final url = Uri.parse('${dotenv.env['API_URL']}/drinks-inventory/drinks-inventoryCategory');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          categories = json.decode(response.body);
        });
      } else {
        throw Exception('Failed to load categories');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching categories: $e"), backgroundColor: Colors.red),
      );
    }
  }

  void _pickDate() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  void _addItem() {
    setState(() {
      items.add({
        "name": "",
        "qty": "",
        "unit": "Bottle",
        "price": "",
        "categoryId": categories.isNotEmpty ? categories[0]['id'] as int : null,
        "bottleSize": "660",
        "nameController": TextEditingController(),
        "qtyController": TextEditingController(),
        "priceController": TextEditingController(),
      });
    });
  }

  void _removeItem(int index) {
    setState(() {
      items.removeAt(index);
    });
  }

  Future<void> _submitPurchase() async {
    setState(() {
      _isLoading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');
    if (token == null) {
      print('No token found. User might not be logged in.');
      return;
    }

    if (_selectedVendor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please select a vendor."), backgroundColor: Colors.red),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final decodedToken = JwtDecoder.decode(token);
    final userId = decodedToken['id'];
    final url = Uri.parse("${dotenv.env['API_URL']}/drinks-purchaseHistory/");
    final request = http.MultipartRequest('POST', url);

    // Standard form fields
    request.fields['date'] = _selectedDate.toIso8601String();
    request.fields['vendor_id'] = _selectedVendor!;
    request.fields['title'] = _titleController.text;
    request.fields['amount'] = _totalAmountController.text;
    request.fields['notes'] = _notesController.text;
    request.fields['user_id'] = userId.toString();

    // Send items as JSON
    if (items.isNotEmpty) {
      final formattedItems = items.map((item) {
        return {
          "name": item["nameController"]?.text ?? item["name"] ?? "",
          "qty": item["qtyController"]?.text ?? item["qty"] ?? "",
          "unit": item["unit"] ?? "Bottle",
          "price": item["priceController"]?.text ?? item["price"] ?? "",
          "categoryId": item["categoryId"] ?? "",
          "bottleSize": item["bottleSize"] ?? "660",
        };
      }).toList();

      request.fields['items'] = jsonEncode(formattedItems);
    }

    // Attach Excel file (if chosen)
    if (_excelFile != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'excel_file',
        _excelFile!.bytes!,
        filename: _excelFile!.name,
      ));
    }

    // Attach image (if chosen)
    if (_selectedImage != null) {
      if (kIsWeb) {
        final bytes = await _selectedImage!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'receipt_image',
          bytes,
          filename: _selectedImage!.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath(
          'receipt_image',
          _selectedImage!.path,
        ));
      }
    }

    try {
      print('--- Purchase Submission Payload ---');
      print('URL: ${request.url}');
      print('Fields: ${request.fields}');
      print('Files: ${request.files.map((f) => f.filename)}');

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      print('Response: ${response.statusCode} → $responseBody');

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Purchase saved successfully!"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save purchase."), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildLabel(String text, {double fontSize = 12}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
          color: Colors.black,
        ),
      ),
    );
  }

  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result != null) {
      setState(() {
        _excelFile = result.files.single;
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    String hint = '',
  }) {
    return TextField(
      controller: controller,
      style: GoogleFonts.poppins(fontSize: 11),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 11),
        filled: true,
        fillColor: Color(0xFFF8F5F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.black, width: 0.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.black, width: 0.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.black, width: 0.4),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
              'Add Drinks Purchase',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Record a new drinks inventory purchase',
              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? Center(
              child: LoadingAnimationWidget.staggeredDotsWave(
                color: Colors.black,
                size: 40,
              ),
            )
          : SingleChildScrollView(
              child: Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(top: 15, bottom: 65),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black, width: 0.4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel('Drinks Purchase Details', fontSize: 13.5),
                      const SizedBox(height: 14),
                      _buildLabel('Date'),
                      GestureDetector(
                        onTap: _pickDate,
                        child: AbsorbPointer(
                          child: TextFormField(
                            controller: TextEditingController(
                              text: DateFormat.yMMMMd().format(_selectedDate),
                            ),
                            style: GoogleFonts.poppins(fontSize: 11),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Color(0xFFF8F5F2),
                              prefixIcon: Icon(
                                Icons.calendar_today,
                                color: Colors.grey[700],
                                size: 16,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.black,
                                  width: 0.4,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.black,
                                  width: 0.4,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.black,
                                  width: 0.4,
                                ),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildLabel('Vendor/Supplier'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F5F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.black, width: 0.4),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedVendor,
                            hint: Text(
                              'Select Vendor',
                              style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 11),
                            ),
                            items: vendors.map<DropdownMenuItem<String>>((vendor) {
                              return DropdownMenuItem<String>(
                                value: vendor['id'].toString(),
                                child: Text(
                                  vendor['name'],
                                  style: GoogleFonts.poppins(fontSize: 11),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              setState(() {
                                _selectedVendor = newValue;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildLabel('Purchase Title'),
                      _buildTextField(controller: _titleController),
                      const SizedBox(height: 16),
                      _buildLabel('Total Amount'),
                      _buildTextField(controller: _totalAmountController),
                      const SizedBox(height: 16),
                      _buildLabel('Receipt Image (Optional)'),
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          height: 55,
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Color(0xFFF8F5F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black, width: 0.4),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: _pickImage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size(0, 32),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: Colors.black, width: 0.4),
                                  ),
                                ),
                                child: Text(
                                  'Choose File',
                                  style: GoogleFonts.poppins(
                                    color: Colors.black,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              _selectedImage != null
                                  ? (kIsWeb
                                      ? Image.network(
                                          _selectedImage!.path,
                                          width: 80,
                                          height: 70,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          File(_selectedImage!.path),
                                          width: 80,
                                          height: 70,
                                          fit: BoxFit.cover,
                                        ))
                                  : Text(
                                      'No file chosen',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                    )
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('Items'),
                      GestureDetector(
                        child: Container(
                          height: 55,
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Color(0xFFF8F5F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black, width: 0.4),
                          ),
                          child: Row(
                            children: [
                              ElevatedButton(
                                onPressed: _addItem,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Colors.black, width: 0.4),
                                  ),
                                ),
                                child: Text(
                                  'Add Item',
                                  style: GoogleFonts.poppins(
                                    color: Colors.black,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  items.isNotEmpty ? '${items.length} item(s) added' : 'No items',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[700],
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_excelFile != null) ...[
                        _buildLabel('Excel File'),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Color(0xFFF8F5F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green, width: 0.4),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _excelFile!.name,
                                  style: GoogleFonts.poppins(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Column(
                        children: List.generate(items.length, (index) {
                          final item = items[index];
                          return Column(
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 140,
                                    child: _buildTextField(
                                      controller: item["nameController"],
                                      hint: 'Item name',
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  SizedBox(
                                    width: 100,
                                    child: _buildTextField(
                                      controller: item["qtyController"],
                                      hint: 'Qty',
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    width: 75,
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: Color(0xFFF8F5F2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: item["bottleSize"],
                                        items: bottleSizes.map<DropdownMenuItem<String>>((String size) {
                                          return DropdownMenuItem<String>(
                                            value: size,
                                            child: Text(size, style: GoogleFonts.poppins(fontSize: 11)),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          setState(() {
                                            item["bottleSize"] = val!;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Container(
                                    width: 160,
                                    padding: EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: Color(0xFFF8F5F2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<int>(
                                        isExpanded: true,
                                        value: item["categoryId"],
                                        items: categories.map<DropdownMenuItem<int>>((category) {
                                          return DropdownMenuItem<int>(
                                            value: category['id'] as int,
                                            child: Text(
                                              category['categoryName'],
                                              style: GoogleFonts.poppins(
                                                color: Colors.black,
                                                fontSize: 10,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (int? val) {
                                          setState(() {
                                            item["categoryId"] = val;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  SizedBox(
                                    width: 100,
                                    child: _buildTextField(
                                      controller: item["priceController"],
                                      hint: 'Price',
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _removeItem(index),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                            ],
                          );
                        }),
                      ),
                      _buildLabel('Notes (Optional)'),
                      _buildTextField(
                        controller: _notesController,
                        hint: 'Add any additional details here...',
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitPurchase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              'Save Purchase',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
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