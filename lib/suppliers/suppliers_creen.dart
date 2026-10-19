import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/suppliers/supplier_products_screen.dart';

class SuppliersScreen extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;

  const SuppliersScreen({
    required this.fullName,
    required this.role,
    required this.userId,
    super.key,
  });

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }



  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supabase
          .from('suppliers')
          .select('*')
          .order('name', ascending: true);

      // Filter on client side if search query exists
      if (_searchQuery.isNotEmpty) {
        final filtered = data.where((supplier) {
          final name = (supplier['name'] ?? '').toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        }).toList();
        setState(() => _suppliers = List<Map<String, dynamic>>.from(filtered));
      } else {
        setState(() => _suppliers = List<Map<String, dynamic>>.from(data));
      }
    } catch (e) {
      print('Error loading suppliers: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddSupplierDialog() {
    showDialog(
      context: context,
      builder: (context) => AddSupplierDialog(
        onSupplierAdded: _loadSuppliers,
      ),
    );
  }

  void _navigateToSupplierProducts(Map<String, dynamic> supplier) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplierProductsScreen(
          supplier: supplier,
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
        ),
      ),
    );
  }

  void _showEditSupplierDialog(Map<String, dynamic> supplier) {
    showDialog(
      context: context,
      builder: (context) => AddSupplierDialog(
        supplier: supplier,
        onSupplierAdded: _loadSuppliers,
      ),
    );
  }

  Future<void> _deleteSupplier(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase.from('suppliers').delete().eq('id', id);
        _loadSuppliers();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supplier deleted'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting supplier: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5C6D3),
        title: const Text(
          'Suppliers',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black87),
            onPressed: _showAddSupplierDialog,
            tooltip: 'Add New Supplier',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _loadSuppliers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: const Icon(Icons.search, color: Colors.pink),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.pink),
                  onPressed: () {
                    _searchController.clear();
                    _searchQuery = '';
                    _loadSuppliers();
                  },
                )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _loadSuppliers();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Total Suppliers: ${_suppliers.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.pink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.pink))
                : _suppliers.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_shipping, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No suppliers found',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        _searchQuery = '';
                        _loadSuppliers();
                      },
                      child: const Text('Clear search'),
                    ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _suppliers.length,
              itemBuilder: (context, index) {
                final supplier = _suppliers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: Colors.pink[100],
                      child: const Icon(
                        Icons.business,
                        color: Colors.pink,
                      ),
                    ),
                    title: Text(
                      supplier['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (supplier['contact_person'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Contact: ${supplier['contact_person']}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        if (supplier['phone'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Phone: ${supplier['phone']}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        if (supplier['email'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Email: ${supplier['email']}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.inventory, color: Colors.pink),
                          onPressed: () {
                            _navigateToSupplierProducts(supplier);
                          },
                          tooltip: 'View Products',
                        ),
                        PopupMenuButton<String>(
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 20, color: Colors.blue),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditSupplierDialog(supplier);
                            } else if (value == 'delete') {
                              _deleteSupplier(
                                supplier['id'],
                                supplier['name'] ?? 'Supplier',
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AddSupplierDialog extends StatefulWidget {
  final Map<String, dynamic>? supplier;
  final VoidCallback onSupplierAdded;

  const AddSupplierDialog({
    this.supplier,
    required this.onSupplierAdded,
    super.key,
  });

  @override
  State<AddSupplierDialog> createState() => _AddSupplierDialogState();
}

class _AddSupplierDialogState extends State<AddSupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.supplier != null) {
      _nameController.text = widget.supplier!['name'] ?? '';
      _contactController.text = widget.supplier!['contact_person'] ?? '';
      _phoneController.text = widget.supplier!['phone'] ?? '';
      _emailController.text = widget.supplier!['email'] ?? '';
    }
  }

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final supplierData = {
        'name': _nameController.text.trim(),
        'contact_person': _contactController.text.trim().isEmpty
            ? null
            : _contactController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'created_at': DateTime.now().toIso8601String(),
      };

      if (widget.supplier != null) {
        await _supabase
            .from('suppliers')
            .update(supplierData)
            .eq('id', widget.supplier!['id']);
      } else {
        await _supabase.from('suppliers').insert(supplierData);
      }

      if (!mounted) return;

      Navigator.pop(context);
      widget.onSupplierAdded();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.supplier != null
              ? 'Supplier updated successfully!'
              : 'Supplier added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving supplier: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.supplier != null ? 'Edit Supplier' : 'Add New Supplier',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Supplier Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business, color: Colors.pink),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter supplier name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Contact Person',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person, color: Colors.pink),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone, color: Colors.pink),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email, color: Colors.pink),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveSupplier,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                          : const Text('Save', style: TextStyle(color: Colors.white)),
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
}