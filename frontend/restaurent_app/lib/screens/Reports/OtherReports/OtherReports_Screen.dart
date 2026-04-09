import 'package:Neevika/screens/Reports/OtherReports/CancelledOrdersReports_Screen.dart';
import 'package:Neevika/screens/Reports/OtherReports/SalesReport_Screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Neevika/screens/Reports/OtherReports/EmployeePerformanceReport_Screen.dart';
import 'package:Neevika/screens/Reports/OtherReports/InventoryReport_Screen.dart';
import 'package:Neevika/screens/Reports/OtherReports/InvoiceReport_Screen.dart';
import 'package:Neevika/screens/Reports/OtherReports/ItemWiseReport_Screen.dart';
import 'package:Neevika/screens/Reports/OtherReports/MasterReport_Screen.dart';
import 'package:Neevika/screens/Reports/OtherReports/SectionWiseReport_Screen.dart';
import 'package:Neevika/screens/Reports/OtherReports/DayWiseReport_Screen.dart';
// import 'package:Neevika/screens/Reports/DayEndSummary.dart';

class AllReportsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> reports = [
    {
      'title': 'Sales Report',
      'screen': SalesReportScreen(),
      'icon': Icons.bar_chart,
    },
    {
      'title': 'Item Wise Report',
      'screen': ItemWiseReportScreen(),
      'icon': Icons.category,
    },
    {
      'title': 'Invoice Report',
      'screen': InvoiceReportScreen(),
      'icon': Icons.receipt_long,
    },
    {
      'title': 'Section Wise Report',
      'screen': SectionWiseReportScreen(),
      'icon': Icons.grid_view,
    },
    {
      'title': 'Cancelled Orders Report',
      'screen': CancelledOrdersReportScreen(),
      'icon': Icons.cancel,
    },
    {
      'title': 'Employee Performance Report',
      'screen': EmployeePerformanceReportScreen(),
      'icon': Icons.people,
    },
    {
      'title': 'Inventory Report',
      'screen': InventoryScreen(),
      'icon': Icons.inventory_2,
    },
    {
      'title': 'Day Wise Report',
      'screen': DayWiseReportScreen(),
      'icon': Icons.calendar_today,
    },
    {
      'title': 'Master Report',
      'screen': DownloadMasterReportScreen(),
      'icon': Icons.file_copy,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth < 600 ? 1 : 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          'All Reports',
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          itemCount: reports.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 2.8,
          ),
          itemBuilder: (context, index) {
            final report = reports[index];
            return _buildReportCard(
              context,
              report['title'],
              report['screen'],
              report['icon'],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReportCard(
    BuildContext context,
    String title,
    Widget screen,
    IconData icon,
  ) {
    return InkWell(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => screen),
          ),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Icon(icon, color: Colors.green.shade600, size: 32),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
