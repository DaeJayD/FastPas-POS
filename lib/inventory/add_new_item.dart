import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddNewItemPage extends StatefulWidget {
  final String? brandId;
  final String? branchId;
  final String? brandName;
  final String? branchName;
  final String? userId;

  const AddNewItemPage({
    super.key,
    this.brandId,
    this.branchId,
    this.brandName,
    this.branchName,
    this.userId,
  });

  @override
  State<AddNewItemPage> createState() => _AddNewItemPageState();
}

class _AddNewItemPageState extends State<AddNewItemPage> {
  final SupabaseClient _supabase = StoreConnection.client;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    if (_nameController.text.isEmpty ||
        _skuController.text.isEmpty ||
        _priceController.text.isEmpty ||
        _quantityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // First, check if category exists or create new one
      String? categoryId;
      if (_categoryController.text.isNotEmpty && widget.brandId != null) {
        final categoryResult = await _supabase
            .from('categories')
            .select('id')
            .eq('name', _categoryController.text)
            .eq('brand_id', widget.brandId!)
            .maybeSingle();

        if (categoryResult != null) {
          categoryId = categoryResult['id'];
        } else {
          // Create new category
          final newCategory = await _supabase.from('categories').insert({
            'brand_id': widget.brandId,
            'name': _categoryController.text,
            'description': 'Auto-generated category',
          }).select();
          categoryId = newCategory[0]['id'];
        }
      }

      // Create the product
      final productResult = await _supabase.from('products').insert({
        'brand_id': widget.brandId,
        'category_id': categoryId,
        'name': _nameController.text,
        'price': double.parse(_priceController.text),
        'sku': _skuController.text,
      }).select();

      final newProductId = productResult[0]['id'];

      // Add stock to the branch
      if (widget.branchId != null) {
        await _supabase.from('branch_stock').insert({
          'product_id': newProductId,
          'branch_id': widget.branchId,
          'current_stock': int.parse(_quantityController.text),
          'low_stock_threshold': 10, // Default threshold
        });
      }

      // Record inventory movement
      if (widget.branchId != null && widget.userId != null) {
        await _supabase.from('inventory_movements').insert({
          'product_id': newProductId,
          'branch_id': widget.branchId,
          'movement_type': 'in',
          'quantity': int.parse(_quantityController.text),
          'previous_stock': 0,
          'new_stock': int.parse(_quantityController.text),
          'user_id': widget.userId, // Use actual user ID
          'reason': 'New product added',
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${_nameController.text} added successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      // Clear form and go back after success
      _nameController.clear();
      _skuController.clear();
      _categoryController.clear();
      _priceController.clear();
      _quantityController.clear();

      // Navigate back after a short delay
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        Navigator.pop(context, true); // Return success
      });
    } catch (e) {
      debugPrint('Error adding item: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error adding item: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Volt.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Add New Item",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.brandName != null && widget.branchName != null)
              Text(
                "${widget.brandName} - ${widget.branchName}",
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product Name
                  const Text(
                    "Product Name *",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: "Enter product name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // SKU
                  const Text(
                    "SKU *",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _skuController,
                    decoration: const InputDecoration(
                      hintText: "Enter unique SKU",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Category
                  const Text(
                    "Category",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      hintText: "Enter category (optional)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Price
                  const Text(
                    "Price *",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      hintText: "0.00",
                      prefixText: "₱",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Quantity
                  const Text(
                    "Initial Quantity *",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: "Enter initial stock quantity",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Add Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Volt.ink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _isLoading ? null : _addItem,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Add Item",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  // Info Text
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "* Required fields\nProduct will be added to the current brand and branch",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
