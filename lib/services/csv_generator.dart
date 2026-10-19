import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../reports/generate_report_page.dart';

class CSVGenerator {
  Future<File> generateSalesReportCSV(List<Map<String, dynamic>> salesData, DateTimeRange dateRange) async {
    final csvData = StringBuffer();

    // Header matching PDF
    csvData.writeln('Vasenizz POS - Sales Report');
    csvData.writeln('Period: ${_formatDate(dateRange.start)} - ${_formatDate(dateRange.end)}');
    csvData.writeln('Generated on: ${_formatDate(DateTime.now())}');
    csvData.writeln();

    // Summary matching PDF
    double totalSales = 0;
    int totalOrders = salesData.length;

    for (final sale in salesData) {
      totalSales += (sale['total_amount'] ?? 0.0);
    }

    csvData.writeln('Summary');
    csvData.writeln('Total Sales,P${totalSales.toStringAsFixed(2)}');
    csvData.writeln('Total Orders,$totalOrders');
    csvData.writeln('Average Order,P${(totalSales / (totalOrders == 0 ? 1 : totalOrders)).toStringAsFixed(2)}');
    csvData.writeln();

    // Data headers matching PDF table
    csvData.writeln('Date,Order ID,Branch,Amount,Items');

    // Data rows matching PDF
    for (final sale in salesData) {
      csvData.writeln([
        _formatDate(DateTime.parse(sale['created_at'])),
        sale['id']?.toString() ?? 'N/A',
        sale['branch_location'] ?? 'Main', // Changed from N/A to Main to match PDF
        'P${(sale['total_amount'] ?? 0.0).toStringAsFixed(2)}',
        (sale['item_count'] ?? 'N/A').toString(),
      ].join(','));
    }

    return await _saveCSV(csvData.toString(), 'sales_report_${DateTime.now().millisecondsSinceEpoch}.csv');
  }

  Future<File> generateInventoryReportCSV(List<Map<String, dynamic>> inventoryData) async {
    final csvData = StringBuffer();

    // Header matching PDF
    csvData.writeln('Vasenizz POS - Inventory Report');
    csvData.writeln('Generated on: ${_formatDate(DateTime.now())}');
    csvData.writeln();

    // Summary matching PDF
    int totalProducts = inventoryData.length;
    int lowStockCount = inventoryData.where((item) => (item['total_stock'] ?? 0) < 8).length; // Changed from 10 to 8
    double totalValue = _calculateInventoryValue(inventoryData);

    csvData.writeln('Summary');
    csvData.writeln('Total Products,$totalProducts');
    csvData.writeln('Low Stock Items,$lowStockCount');
    csvData.writeln('Total Value,P${totalValue.toStringAsFixed(2)}'); // Added P prefix to match PDF
    csvData.writeln();

    // Data headers matching PDF table
    csvData.writeln('Product Name,Brand,Quantity,Price,Status');

    // Data rows matching PDF
    for (final item in inventoryData) {
      final stock = item['total_stock'] ?? 0;
      final status = stock == 0 ? 'OUT OF STOCK' : stock <= 8 ? 'LOW STOCK' : 'IN STOCK';

      csvData.writeln([
        item['name'] ?? 'N/A',
        item['brand_name'] ?? 'N/A',
        stock.toString(),
        'P${(item['price'] ?? 0.0).toStringAsFixed(2)}',
        status,
      ].join(','));
    }

    return await _saveCSV(csvData.toString(), 'inventory_report_${DateTime.now().millisecondsSinceEpoch}.csv');
  }

  Future<File> generateAttendanceReportCSV(List<Map<String, dynamic>> attendanceData, DateTimeRange dateRange) async {
    final csvData = StringBuffer();

    // Header matching PDF
    csvData.writeln('Vasenizz POS - Attendance Report');
    csvData.writeln('Period: ${_formatDate(dateRange.start)} - ${_formatDate(dateRange.end)}');
    csvData.writeln('Generated on: ${_formatDate(DateTime.now())}');
    csvData.writeln();

    // Summary matching PDF
    int totalRecords = attendanceData.length;
    int completedShifts = attendanceData.where((record) => record['time_out'] != null).length;

    csvData.writeln('Summary');
    csvData.writeln('Total Records,$totalRecords');
    csvData.writeln('Completed Shifts,$completedShifts');
    csvData.writeln('Pending Time Out,${totalRecords - completedShifts}');
    csvData.writeln();

    // Data headers matching PDF table
    csvData.writeln('Date,Employee,Time In,Time Out,Status');

    // Data rows matching PDF
    for (final record in attendanceData) {
      final employee = record['employees'] is Map ? record['employees']['name'] : 'N/A';
      final timeIn = record['time_in'] != null ? _formatTime(DateTime.parse(record['time_in'])) : 'N/A';
      final timeOut = record['time_out'] != null ? _formatTime(DateTime.parse(record['time_out'])) : 'Pending';

      csvData.writeln([
        record['date'] ?? 'N/A',
        employee,
        timeIn,
        timeOut,
        record['time_out'] != null ? 'Completed' : 'On Duty',
      ].join(','));
    }

    return await _saveCSV(csvData.toString(), 'attendance_report_${DateTime.now().millisecondsSinceEpoch}.csv');
  }

  // Helper methods matching PDF generator
  double _calculateInventoryValue(List<Map<String, dynamic>> inventoryData) {
    double totalValue = 0;
    for (final item in inventoryData) {
      totalValue += (item['price'] ?? 0.0) * (item['total_stock'] ?? 0);
    }
    return totalValue;
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}'; // Changed from dd/mm/yyyy to mm/dd/yyyy to match PDF
  }

  String _formatTime(DateTime date) {
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}'; // Matches PDF format
  }

  Future<File> _saveCSV(String csvContent, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(csvContent);
    return file;
  }

  // Optional: Add method to open CSV file after generation
  Future<void> openCSVFile(File file) async {
    await OpenFile.open(file.path);
  }
}