import 'package:vasenizzpos/core/management_ui.dart';
import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:open_file/open_file.dart';

import '../services/pdf_generator.dart';
import '../services/csv_generator.dart';

// Add DateTimeRange class at the top of the file
class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({required this.start, required this.end});
}

class GenerateReportPage extends StatefulWidget {
  const GenerateReportPage({super.key});

  @override
  State<GenerateReportPage> createState() => _GenerateReportPageState();
}

class _GenerateReportPageState extends State<GenerateReportPage> {
  final supabase = StoreConnection.client;
  final PDFGenerator _pdfGenerator = PDFGenerator();
  final CSVGenerator _csvGenerator = CSVGenerator();

  String selectedDateRange = "Last Week";
  String selectedFormat = "PDF";
  String selectedCategory = "Sales";
  DateTimeRange? customDateRange;
  bool _isGenerating = false;

  final List<String> dateRangeOptions = [
    "Last Week",
    "Last Month",
    "Last 3 Months",
    "Last 6 Months",
    "Last Year",
    "Custom Range",
  ];

  final List<String> formatOptions = ["PDF", "CSV"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Volt.background,
      appBar: AppBar(
        backgroundColor: Volt.background,
        title: const Text(
          "Generate Reports",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isGenerating
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(18),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Report Configuration",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                      ),
                      child: Column(
                        children: [
                          ManagementColumns(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _dropdownField(
                                "Date Range",
                                selectedDateRange,
                                dateRangeOptions,
                                (value) {
                                  setState(() => selectedDateRange = value!);
                                  if (value == "Custom Range") {
                                    _showDateRangePicker();
                                  }
                                },
                              ),
                              const SizedBox(width: 10),
                              _dropdownField(
                                "Export Format",
                                selectedFormat,
                                formatOptions,
                                (value) {
                                  setState(() => selectedFormat = value!);
                                },
                              ),
                            ],
                          ),
                          if (customDateRange != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              "Custom Range: ${_formatDate(customDateRange!.start)} - ${_formatDate(customDateRange!.end)}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _reportCard(
                      Icons.pie_chart_rounded,
                      "Sales Report",
                      "Summary of sales analytics and performance",
                      onGenerate: () => _generateSalesReport(),
                    ),
                    _reportCard(
                      Icons.inventory_2_rounded,
                      "Inventory Summary Report",
                      "Overview of current stock levels and valuation",
                      onGenerate: () => _generateInventoryReport(),
                    ),
                    _reportCard(
                      Icons.list_alt,
                      "Total Stock Report",
                      "Detailed analysis of stock movement and turnover",
                      onGenerate: () => _generateStockReport(),
                    ),
                    _reportCard(
                      Icons.group,
                      "Employee Attendance Report",
                      "Logs of employee time-in and time-out records",
                      onGenerate: () => _generateAttendanceReport(),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      "Recent Reports",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _recentReportCard(
                      "Sales Report – ${_getCurrentMonth()}",
                      DateTime.now().subtract(const Duration(days: 2)),
                      "PDF",
                      "2.3 MB",
                    ),
                    _recentReportCard(
                      "Inventory Summary – ${_getLastMonth()}",
                      DateTime.now().subtract(const Duration(days: 5)),
                      "PDF",
                      "1.8 MB",
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _dropdownField(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black26),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                items: options
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportCard(
    IconData icon,
    String title,
    String desc, {
    required VoidCallback onGenerate,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: Row(
        children: [
          Icon(icon, size: 35, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(desc, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          Column(
            children: [
              _smallButton("Preview", onPressed: () => _previewReport(title)),
              const SizedBox(height: 6),
              _smallButton("Generate", primary: true, onPressed: onGenerate),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallButton(
    String text, {
    bool primary = false,
    VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF1E88E5) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: primary ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _recentReportCard(
    String title,
    DateTime date,
    String format,
    String size,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  "Generated on ${_formatDate(date)} • $format • $size",
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          _smallButton(
            "Download",
            primary: true,
            onPressed: () => _downloadReport(title),
          ),
        ],
      ),
    );
  }

  void _showDateRangePicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Select Date Range"),
        content: SizedBox(
          width: 400,
          height: 400,
          child: SfDateRangePicker(
            selectionMode: DateRangePickerSelectionMode.range,
            onSelectionChanged: (DateRangePickerSelectionChangedArgs args) {
              if (args.value is PickerDateRange) {
                final range = args.value as PickerDateRange;
                if (range.startDate != null && range.endDate != null) {
                  setState(() {
                    customDateRange = DateTimeRange(
                      start: range.startDate!,
                      end: range.endDate!,
                    );
                  });
                  Navigator.pop(context);
                }
              }
            },
          ),
        ),
      ),
    );
  }

  Future<void> _generateSalesReport() async {
    setState(() => _isGenerating = true);

    try {
      final dateRange = _getSelectedDateRange();

      // Fetch sales data with item count
      final salesResponse = await supabase
          .from('sales')
          .select('''
            *,
            sale_items(count)
          ''')
          .gte('created_at', dateRange.start.toIso8601String())
          .lte('created_at', dateRange.end.toIso8601String())
          .order('created_at', ascending: false);

      final salesData = List<Map<String, dynamic>>.from(salesResponse);

      // Process data to include item count
      final processedSalesData = salesData.map((sale) {
        final saleItems = sale['sale_items'] as List?;
        return {...sale, 'item_count': saleItems?.length ?? 0};
      }).toList();

      // Generate report based on selected format
      if (selectedFormat == "PDF") {
        final pdfFile = await _pdfGenerator.generateSalesReport(
          dateRange,
          processedSalesData,
        );
        await OpenFile.open(pdfFile.path);
      } else if (selectedFormat == "CSV") {
        final csvFile = await _csvGenerator.generateSalesReportCSV(
          processedSalesData,
          dateRange,
        );
        await OpenFile.open(csvFile.path);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Sales report generated successfully in $selectedFormat format!",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generating sales report: $e")),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateInventoryReport() async {
    setState(() => _isGenerating = true);

    try {
      final inventoryResponse = await supabase
          .from('product_inventory_summary')
          .select('*')
          .order('name');

      final inventoryData = List<Map<String, dynamic>>.from(inventoryResponse);

      if (selectedFormat == "PDF") {
        final pdfFile = await _pdfGenerator.generateInventoryReport(
          inventoryData,
        );
        await OpenFile.open(pdfFile.path);
      } else if (selectedFormat == "CSV") {
        final csvFile = await _csvGenerator.generateInventoryReportCSV(
          inventoryData,
        );
        await OpenFile.open(csvFile.path);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Inventory report generated successfully in $selectedFormat format!",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generating inventory report: $e")),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateStockReport() async {
    setState(() => _isGenerating = true);

    try {
      final stockResponse = await supabase
          .from('product_inventory_summary')
          .select('*')
          .order('total_stock');

      final stockData = List<Map<String, dynamic>>.from(stockResponse);

      if (selectedFormat == "PDF") {
        final pdfFile = await _pdfGenerator.generateInventoryReport(stockData);
        await OpenFile.open(pdfFile.path);
      } else if (selectedFormat == "CSV") {
        final csvFile = await _csvGenerator.generateInventoryReportCSV(
          stockData,
        );
        await OpenFile.open(csvFile.path);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Stock report generated successfully in $selectedFormat format!",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generating stock report: $e")),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateAttendanceReport() async {
    setState(() => _isGenerating = true);

    try {
      final dateRange = _getSelectedDateRange();

      final attendanceResponse = await supabase
          .from('attendance')
          .select('''
            *,
            employees(name)
          ''')
          .gte('date', dateRange.start.toIso8601String().split('T')[0])
          .lte('date', dateRange.end.toIso8601String().split('T')[0])
          .order('date', ascending: false);

      final attendanceData = List<Map<String, dynamic>>.from(
        attendanceResponse,
      );

      if (selectedFormat == "PDF") {
        final pdfFile = await _pdfGenerator.generateAttendanceReport(
          dateRange,
          attendanceData,
        );
        await OpenFile.open(pdfFile.path);
      } else if (selectedFormat == "CSV") {
        final csvFile = await _csvGenerator.generateAttendanceReportCSV(
          attendanceData,
          dateRange,
        );
        await OpenFile.open(csvFile.path);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Attendance report generated successfully in $selectedFormat format!",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generating attendance report: $e")),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  void _previewReport(String reportName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("$reportName Preview"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Report Type: $reportName"),
            Text("Date Range: $selectedDateRange"),
            Text("Format: $selectedFormat"),
            Text("Category: $selectedCategory"),
            const SizedBox(height: 10),
            const Text(
              "Preview will show the first few records of the report.",
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Trigger actual generation
              switch (reportName) {
                case "Sales Report":
                  _generateSalesReport();
                  break;
                case "Inventory Summary Report":
                  _generateInventoryReport();
                  break;
                case "Total Stock Report":
                  _generateStockReport();
                  break;
                case "Employee Attendance Report":
                  _generateAttendanceReport();
                  break;
              }
            },
            child: const Text("Generate Full Report"),
          ),
        ],
      ),
    );
  }

  void _downloadReport(String reportName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Downloading $reportName..."),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  DateTimeRange _getSelectedDateRange() {
    final now = DateTime.now();
    switch (selectedDateRange) {
      case "Last Week":
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 7),
          end: now,
        );
      case "Last Month":
        return DateTimeRange(
          start: DateTime(now.year, now.month - 1, now.day),
          end: now,
        );
      case "Last 3 Months":
        return DateTimeRange(
          start: DateTime(now.year, now.month - 3, now.day),
          end: now,
        );
      case "Last 6 Months":
        return DateTimeRange(
          start: DateTime(now.year, now.month - 6, now.day),
          end: now,
        );
      case "Last Year":
        return DateTimeRange(
          start: DateTime(now.year - 1, now.month, now.day),
          end: now,
        );
      case "Custom Range":
        return customDateRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, now.day - 7),
              end: now,
            );
      default:
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day - 7),
          end: now,
        );
    }
  }

  String _formatDate(DateTime date) {
    return "${date.month}/${date.day}/${date.year}";
  }

  String _getCurrentMonth() {
    final now = DateTime.now();
    return "${now.month}/${now.year}";
  }

  String _getLastMonth() {
    final lastMonth = DateTime.now().subtract(const Duration(days: 30));
    return "${lastMonth.month}/${lastMonth.year}";
  }
}
