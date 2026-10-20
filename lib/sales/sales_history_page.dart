import 'sales_repository.dart';
import '../core/management_ui.dart';
import '../catalog/catalog_source.dart';

import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'receipt_page.dart';

class SalesHistoryPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;

  const SalesHistoryPage({
    super.key,
    required this.fullName,
    required this.userId,
    required this.location,
    required this.role,
  });

  @override
  State<SalesHistoryPage> createState() => _SalesHistoryPageState();
}

class _SalesHistoryPageState extends State<SalesHistoryPage> {
  final _repository = SalesRepository();
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _filteredSales = [];
  bool _isLoading = true;
  bool _hasError = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSalesHistory();
    _searchController.addListener(_filterSales);
  }

  Future<void> _loadSalesHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final response = await _repository.history();
      if (!mounted) return;
      setState(() {
        _sales = List<Map<String, dynamic>>.from(response);
        _filteredSales = _sales;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _filterSales() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSales = _sales;
      } else {
        _filteredSales = _sales.where((sale) {
          final saleId = sale['id']?.toString().toLowerCase() ?? '';
          final totalAmount = sale['total_amount']?.toString() ?? '';
          final paymentMethod =
              sale['payment_method']?.toString().toLowerCase() ?? '';
          final cashierName =
              sale['cashier_name']?.toString().toLowerCase() ?? '';
          final date = _formatDate(sale['created_at']?.toString() ?? '')
              .toLowerCase();
          final time = _formatTime(sale['created_at']?.toString() ?? '')
              .toLowerCase();

          return saleId.contains(query) ||
              totalAmount.contains(query) ||
              paymentMethod.contains(query) ||
              cashierName.contains(query) ||
              date.contains(query) ||
              time.contains(query);
        }).toList();
      }
    });
  }

  String _formatDate(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString).toLocal();
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  String _formatTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString).toLocal();
      return DateFormat('hh:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid Time';
    }
  }

  Future<void> _viewSaleDetails(Map<String, dynamic> sale) async {
    try {
      final lines = await _repository.lines(sale['id'].toString());
      if (!mounted) return;
      double amount(String key) => (sale[key] as num?)?.toDouble() ?? 0;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPage(
            userId: widget.userId,
            location: sale['branch_location'] ?? widget.location,
            saleId: sale['id'].toString(),
            paymentMethod: sale['payment_method'] ?? 'Cash',
            subtotal: amount('subtotal_amount'),
            tax: amount('tax_amount'),
            discount: amount('discount_amount'),
            total: amount('total_amount'),
            cartItems: lines.map((line) => line.toCart()).toList(),
            fullName: sale['cashier_name'] ?? 'Unknown',
            role: widget.role,
            cashGiven: amount('cash_given'),
            change: amount('change'),
            preview: StoreConnection.isPreview,
            historical: true,
            createdAt: DateTime.tryParse(sale['created_at']?.toString() ?? ''),
            cashRecorded: sale['cash_given'] != null,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load this receipt. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const ManagementTitle('Sales history', subtitle: 'All branches'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loadSalesHistory,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _loadSalesHistory,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search receipts, cashier or date',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 20),
          if (!_isLoading && !_hasError) ...[
            ManagementColumns(
              children: [
                _metric(
                  'Receipts',
                  _filteredSales.length.toString(),
                  Icons.receipt_long_outlined,
                ),
                _metric(
                  'Revenue',
                  pesos(
                    _filteredSales.fold<num>(
                      0,
                      (sum, sale) =>
                          sum + ((sale['total_amount'] as num?) ?? 0),
                    ),
                  ),
                  Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _searchController.text.isEmpty
                  ? 'Recent transactions'
                  : 'Search results',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          ],
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasError)
            _message(
              'Could not load sales history',
              action: TextButton(
                onPressed: _loadSalesHistory,
                child: const Text('Retry'),
              ),
            )
          else if (_filteredSales.isEmpty)
            _message(
              _searchController.text.isEmpty
                  ? 'No sales recorded yet'
                  : 'No matching receipts',
            )
          else
            for (final sale in _filteredSales)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _viewSaleDetails(sale),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                pesos((sale['total_amount'] as num?) ?? 0),
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Chip(
                                label: Text(
                                  sale['payment_method']
                                          ?.toString()
                                          .toUpperCase() ??
                                      'CASH',
                                ),
                                backgroundColor: Volt.soft,
                                side: BorderSide.none,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_formatDate(sale['created_at']?.toString() ?? '')} · ${_formatTime(sale['created_at']?.toString() ?? '')}',
                            style: const TextStyle(color: Volt.muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${sale['branch_location'] ?? 'Unknown branch'} · ${sale['cashier_name'] ?? 'Unknown cashier'}',
                          ),
                          const SizedBox(height: 8),
                          const Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'View receipt',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Icon(Icons.arrow_forward, size: 18),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(label, style: const TextStyle(color: Volt.muted)),
        ],
      ),
    ),
  );

  Widget _message(String text, {Widget? action}) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        const Icon(Icons.receipt_long_outlined, size: 40, color: Volt.muted),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
        if (action != null) action,
      ],
    ),
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
