import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class SupplierProductsScreen extends StatefulWidget {
  final Map<String, dynamic> supplier;
  final String fullName;
  final String role;
  final String userId;

  const SupplierProductsScreen({
    required this.supplier,
    required this.fullName,
    required this.role,
    required this.userId,
    super.key,
  });

  @override
  State<SupplierProductsScreen> createState() => _SupplierProductsScreenState();
}

class _SupplierProductsScreenState extends State<SupplierProductsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _supplierProducts = [];
  List<Map<String, dynamic>> _allProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final supplierProductsData = await _supabase
          .from('products')
          .select('*')
          .eq('supplier_id', widget.supplier['id'])
          .order('name', ascending: true);

      final allProductsData = await _supabase
          .from('products')
          .select('*')
          .order('name', ascending: true);

      setState(() {
        _supplierProducts = List<Map<String, dynamic>>.from(supplierProductsData);
        _allProducts = List<Map<String, dynamic>>.from(allProductsData);
      });
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _assignProductToSupplier(String productId) async {
    try {
      final price = await _showPriceDialog();
      if (price == null) return;

      await _supabase
          .from('products')
          .update({
        'supplier_id': widget.supplier['id'],
        'supplier_price': price,
      })
          .eq('id', productId);

      await _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Product assigned to supplier'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeProductFromSupplier(String productId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove Product',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to remove this product from supplier?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase
            .from('products')
            .update({
          'supplier_id': null,
          'supplier_price': null,
        })
            .eq('id', productId);

        await _loadData();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Product removed from supplier'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updateSupplierPrice(String productId, double currentPrice) async {
    final price = await _showPriceDialog(initialPrice: currentPrice);
    if (price == null) return;

    try {
      await _supabase
          .from('products')
          .update({'supplier_price': price})
          .eq('id', productId);

      await _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Price updated successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<double?> _showPriceDialog({double? initialPrice}) async {
    final controller = TextEditingController(text: initialPrice?.toString() ?? '');

    return await showDialog<double>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Supplier Price',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Cost Price',
                  prefixText: '₱',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFF5C6D3)),
                  ),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final price = double.tryParse(controller.text);
                        if (price != null && price > 0) {
                          Navigator.pop(context, price);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5C6D3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  void _showAddProductDialog() {
    final availableProducts = _allProducts
        .where((product) => product['supplier_id'] == null ||
        product['supplier_id'] == widget.supplier['id'])
        .toList();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          height: 500,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Assign Product',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a product to assign to this supplier',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    border: InputBorder.none,
                    prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                      onPressed: () {},
                    ),
                  ),
                  onChanged: (query) {
                    // Implement search functionality
                  },
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: availableProducts.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.inventory, size: 60, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'All products are assigned',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  itemCount: availableProducts.length,
                  itemBuilder: (context, index) {
                    final product = availableProducts[index];
                    final alreadyAssigned = product['supplier_id'] == widget.supplier['id'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade200,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: alreadyAssigned ? Colors.green.shade50 : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            alreadyAssigned ? Icons.check_circle : Icons.inventory_2,
                            color: alreadyAssigned ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          product['name'] ?? 'Unknown',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: alreadyAssigned ? Colors.green : Colors.black87,
                          ),
                        ),
                        subtitle: Text(
                          '₱${(product['price'] ?? 0).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        trailing: alreadyAssigned
                            ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Assigned',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                            : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                        onTap: alreadyAssigned
                            ? null
                            : () {
                          Navigator.pop(context);
                          _assignProductToSupplier(product['id']);
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
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

  Widget _buildSupplierInfoCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C6D3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.business,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.supplier['name'] ?? 'Unknown Supplier',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_supplierProducts.length} Products',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8EDF3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory,
                      size: 14,
                      color: Colors.pink[300],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Supplier',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.pink[300],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              if (widget.supplier['contact_person'] != null)
                _buildInfoItem(
                  icon: Icons.person_outline,
                  label: 'Contact',
                  value: widget.supplier['contact_person'],
                ),
              if (widget.supplier['phone'] != null)
                _buildInfoItem(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: widget.supplier['phone'],
                ),
              if (widget.supplier['email'] != null)
                _buildInfoItem(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: widget.supplier['email'],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(int index) {
    final product = _supplierProducts[index];
    final supplierPrice = (product['supplier_price'] ?? 0).toDouble();
    final salePrice = (product['price'] ?? 0).toDouble();
    final profit = salePrice - supplierPrice;
    final margin = supplierPrice > 0 ? (profit / supplierPrice * 100) : 0;
    final profitColor = profit > 0 ? Colors.green : Colors.red;
    final marginColor = margin > 20
        ? Colors.green
        : margin > 10
        ? Colors.orange
        : Colors.red;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.pink[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.shopping_bag,
                  color: Colors.pink[300],
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? 'Unknown Product',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (product['category'] != null)
                      Text(
                        product['category'],
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit_price',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18, color: Colors.blue[400]),
                        const SizedBox(width: 8),
                        const Text('Edit Price'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                        const SizedBox(width: 8),
                        const Text('Remove'),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'edit_price') {
                    _updateSupplierPrice(product['id'], supplierPrice);
                  } else if (value == 'remove') {
                    _removeProductFromSupplier(product['id']);
                  }
                },
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPriceColumn(
                  label: 'Cost Price',
                  value: supplierPrice,
                  color: Colors.pink[300]!,
                  icon: Icons.price_change_outlined,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.grey.shade300,
                ),
                _buildPriceColumn(
                  label: 'Sale Price',
                  value: salePrice,
                  color: Colors.green,
                  icon: Icons.sell_outlined,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.grey.shade300,
                ),
                _buildPriceColumn(
                  label: 'Profit',
                  value: profit,
                  color: profitColor,
                  icon: Icons.trending_up_outlined,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.grey.shade300,
                ),
                _buildPriceColumn(
                  label: 'Margin',
                  value: margin,
                  color: marginColor,
                  isPercent: true,
                  icon: Icons.percent_outlined,
                ),
              ],
            ),
          ),
          if (product['barcode'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.qr_code, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Barcode: ${product['barcode']}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPriceColumn({
    required String label,
    required double value,
    required Color color,
    required IconData icon,
    bool isPercent = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          isPercent ? '${value.toStringAsFixed(1)}%' : '₱${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5C6D3),
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Supplier Products',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.add, color: Colors.black87),
            onPressed: _showAddProductDialog,
            tooltip: 'Assign Product',
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.black87),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF5C6D3),
          strokeWidth: 2,
        ),
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSupplierInfoCard(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Products List',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    '${_supplierProducts.length} items',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _supplierProducts.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.inventory_outlined,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No Products Assigned',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add products to this supplier to get started',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _showAddProductDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5C6D3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    ),
                    child: const Text(
                      'Assign First Product',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: _supplierProducts.length,
              itemBuilder: (context, index) => _buildProductItem(index),
            ),
          ),
        ],
      ),
    );
  }
}