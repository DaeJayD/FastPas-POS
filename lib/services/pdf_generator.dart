import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../reports/generate_report_page.dart'; // This imports DateTimeRange from the same file


class PDFGenerator {
  Future<File> generateSalesReport(DateTimeRange dateRange, List<Map<String, dynamic>> salesData) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          _buildHeader('Sales Report', dateRange),
          _buildSalesSummary(salesData),
          pw.SizedBox(height: 20),
          _buildSalesTable(salesData),
          _buildFooter(),
        ],
      ),
    );

    return await _savePDF(pdf, 'sales_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  Future<File> generateInventoryReport(List<Map<String, dynamic>> inventoryData) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          _buildHeader('Inventory Report', null),
          _buildInventorySummary(inventoryData),
          pw.SizedBox(height: 20),
          _buildInventoryTable(inventoryData),
          _buildFooter(),
        ],
      ),
    );

    return await _savePDF(pdf, 'inventory_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  Future<File> generateAttendanceReport(DateTimeRange dateRange, List<Map<String, dynamic>> attendanceData) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => [
          _buildHeader('Attendance Report', dateRange),
          _buildAttendanceSummary(attendanceData),
          pw.SizedBox(height: 20),
          _buildAttendanceTable(attendanceData),
          _buildFooter(),
        ],
      ),
    );

    return await _savePDF(pdf, 'attendance_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  }

  pw.Widget _buildHeader(String title, DateTimeRange? dateRange) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Vasenizz POS',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Report: $title',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        if (dateRange != null)
          pw.Text(
            'Period: ${_formatDate(dateRange.start)} - ${_formatDate(dateRange.end)}',
            style: pw.TextStyle(fontSize: 12),
          ),
        pw.Divider(),
        pw.SizedBox(height: 20),
      ],
    );
  }

  pw.Widget _buildSalesSummary(List<Map<String, dynamic>> salesData) {
    double totalSales = 0;
    int totalOrders = salesData.length;

    for (final sale in salesData) {
      totalSales += (sale['total_amount'] ?? 0.0);
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total Sales', 'P${totalSales.toStringAsFixed(2)}'),
          _buildSummaryItem('Total Orders', totalOrders.toString()),
          _buildSummaryItem('Average Order', 'P${(totalSales / (totalOrders == 0 ? 1 : totalOrders)).toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  pw.Widget _buildSalesTable(List<Map<String, dynamic>> salesData) {
    final headers = ['Date', 'Order ID', 'Branch', 'Amount', 'Items'];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: salesData.map((sale) => [
        _formatDate(DateTime.parse(sale['created_at'])),
        sale['id']?.toString() ?? 'N/A',
        sale['branch_location'] ?? 'Main',
        'P${(sale['total_amount'] ?? 0.0).toStringAsFixed(2)}',
        (sale['item_count'] ?? 'N/A').toString(),
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  pw.Widget _buildInventorySummary(List<Map<String, dynamic>> inventoryData) {
    int totalProducts = inventoryData.length;
    int lowStockCount = inventoryData.where((item) => (item['total_stock'] ?? 0) < 8).length;

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total Products', totalProducts.toString()),
          _buildSummaryItem('Low Stock Items', lowStockCount.toString()),
          _buildSummaryItem('Total Value', _calculateInventoryValue(inventoryData)),
        ],
      ),
    );
  }

  pw.Widget _buildInventoryTable(List<Map<String, dynamic>> inventoryData) {
    final headers = ['Product Name', 'Brand', 'Quantity', 'Price', 'Status'];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: inventoryData.map((item) {
        final stock = item['total_stock'] ?? 0;
        final status = stock == 0 ? 'OUT OF STOCK' : stock <= 8 ? 'LOW STOCK' : 'IN STOCK';
        final statusColor = stock == 0 ? PdfColors.red : stock <= 8 ? PdfColors.orange : PdfColors.green;

        return [
          item['name'] ?? 'N/A',
          item['brand_name'] ?? 'N/A',
          (item['total_stock'] ?? 0).toString(),
          'P${(item['price'] ?? 0.0).toStringAsFixed(2)}',
          pw.Text(
            status,
            style: pw.TextStyle(color: statusColor, fontWeight: pw.FontWeight.bold),
          ),
        ];
      }).toList(),
      cellStyle: pw.TextStyle(fontSize: 10),
      headerStyle: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
    );
  }

  pw.Widget _buildAttendanceSummary(List<Map<String, dynamic>> attendanceData) {
    int totalRecords = attendanceData.length;
    int completedShifts = attendanceData.where((record) => record['time_out'] != null).length;

    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Total Records', totalRecords.toString()),
          _buildSummaryItem('Completed Shifts', completedShifts.toString()),
          _buildSummaryItem('Pending Time Out', (totalRecords - completedShifts).toString()),
        ],
      ),
    );
  }

  pw.Widget _buildAttendanceTable(List<Map<String, dynamic>> attendanceData) {
    final headers = ['Date', 'Employee', 'Time In', 'Time Out', 'Status'];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: attendanceData.map((record) {
        final employee = record['employees'] is Map ? record['employees']['name'] : 'N/A';
        final timeIn = record['time_in'] != null ? _formatTime(DateTime.parse(record['time_in'])) : 'N/A';
        final timeOut = record['time_out'] != null ? _formatTime(DateTime.parse(record['time_out'])) : 'Pending';

        return [
          record['date'] ?? 'N/A',
          employee,
          timeIn,
          timeOut,
          record['time_out'] != null ? 'Completed' : 'On Duty',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  pw.Widget _buildSummaryItem(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 30),
      child: pw.Column(
        children: [
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Text(
            'Generated on ${_formatDate(DateTime.now())}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
          ),
        ],
      ),
    );
  }

  String _calculateInventoryValue(List<Map<String, dynamic>> inventoryData) {
    double totalValue = 0;
    for (final item in inventoryData) {
      totalValue += (item['price'] ?? 0.0) * (item['total_stock'] ?? 0);
    }
    return 'P${totalValue.toStringAsFixed(2)}';
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<File> _savePDF(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }
}