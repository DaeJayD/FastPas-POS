import 'package:vasenizzpos/core/management_ui.dart';

import 'report_repository.dart';

import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'generate_report_page.dart';
import 'logs.dart';

class ViewReportsPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final int initialIndex;

  const ViewReportsPage({
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.initialIndex = 3,
    super.key,
  });

  @override
  State<ViewReportsPage> createState() => _ViewReportsPageState();
}

class _ViewReportsPageState extends State<ViewReportsPage> {
  String selectedRange = "1W";
  final _repository = ReportRepository();
  SalesReport _report = const SalesReport();
  bool _isLoading = true, _hasError = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    final request = ++_request;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final report = await _repository.load(selectedRange);
      if (!mounted || request != _request) return;
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Volt.background, // Same as inventory page
      appBar: AppBar(
        title: ManagementTitle(
          'Sales reports',
          subtitle: '${widget.fullName} · ${widget.role}',
        ),
        actions: [
          IconButton(
            tooltip: 'Activity logs',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ActivityLogsPage(logs: []),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadReportData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
          ? Center(
              child: TextButton(
                onPressed: _loadReportData,
                child: const Text('Could not load reports. Retry'),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // UNIFORM BUTTONS
                  Row(
                    children: [
                      Expanded(child: _tabButton("Analytics Dashboard", true)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _tabButton(
                          "Generate Report",
                          false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const GenerateReportPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Sales Overview",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Divider(thickness: 1),
                  const SizedBox(height: 10),
                  ManagementColumns(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statCard(
                        Icons.store,
                        _report.orders.toString(),
                        "Total Orders",
                        Volt.soft,
                      ),
                      _statCard(
                        Icons.attach_money,
                        "₱${_report.total.toStringAsFixed(2)}",
                        "In-Store Total Sales",
                        Volt.soft,
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Center(
                    child: Wrap(
                      spacing: 6,
                      children: ["1D", "1W", "1M", "3M", "6M", "1Yr"]
                          .map(
                            (r) => ChoiceChip(
                              label: Text(r),
                              selected: selectedRange == r,
                              selectedColor: Volt.soft,
                              onSelected: (_) {
                                setState(() => selectedRange = r);
                                _loadReportData(); // Reload data when range changes
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "Revenue",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        "₱${_report.total.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Chip(
                        label: Text(
                          "${_report.changePercent >= 0 ? '+' : ''}${_report.changePercent.toStringAsFixed(1)}%",
                        ),
                        backgroundColor: _report.changePercent >= 0
                            ? const Color(0xFFD8F9D4)
                            : const Color(0xFFFFE0E0),
                        labelStyle: TextStyle(
                          color: _report.changePercent >= 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildLineChart(),
                  const SizedBox(height: 30),
                  const Text(
                    "Top Selling Products",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Divider(thickness: 1),
                  const SizedBox(height: 15),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 210,
                    children: _report.topProducts
                        .map(
                          (product) => _topSellingProductCard(
                            product.name,
                            product.quantity.toString(),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: null,
    );
  }

  Widget _buildLineChart() {
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 6,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index > 6) return const SizedBox.shrink();
                  const days = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ];
                  final day = DateTime.now().subtract(
                    Duration(days: 6 - index),
                  );
                  return Text(days[day.weekday - 1]);
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < _report.dailyTotals.length; i++)
                  FlSpot(i.toDouble(), _report.dailyTotals[i]),
              ],
              color: Volt.ink,
              barWidth: 3,
              isCurved: true,
              belowBarData: BarAreaData(
                show: true,
                color: Volt.ink.withValues(alpha: 0.2),
              ),
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topSellingProductCard(String productName, String salesCount) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Volt.soft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory_2, color: Volt.ink),
          ),
          const SizedBox(height: 8),
          Text(
            productName,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_upward, color: Colors.green, size: 16),
              Text(
                salesCount,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(" sold", style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool active, {VoidCallback? onTap}) {
    return ElevatedButton(
      onPressed: onTap ?? () {},
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? Volt.soft : Colors.grey.shade200,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(label, style: TextStyle(color: Volt.ink, fontSize: 13)),
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color bgColor) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.black54, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
