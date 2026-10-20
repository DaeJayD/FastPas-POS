import 'package:flutter/material.dart';

import '../../branches/branch_repository.dart';
import '../../catalog/catalog_source.dart';
import '../../core/management_ui.dart';
import '../brand_inventory.dart';

class BranchInventoryScreen extends StatefulWidget {
  const BranchInventoryScreen({
    super.key,
    required this.fullName,
    required this.role,
    required this.location,
    required this.userId,
    required this.branchName,
    this.branch,
    this.repository,
  });
  final String fullName, role, location, userId, branchName;
  final StoreBranch? branch;
  final BranchRepository? repository;
  @override
  State<BranchInventoryScreen> createState() => _BranchInventoryScreenState();
}

class _BranchInventoryScreenState extends State<BranchInventoryScreen> {
  late final _repository = widget.repository ?? BranchRepository();
  StoreBranch? _branch;
  List<BranchBrand> _brands = [];
  bool _loading = true, _error = false;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final branch =
          widget.branch ?? await _repository.findByName(widget.branchName);
      final brands = await _repository.brands(branch.id);
      if (!mounted) return;
      setState(() {
        _branch = branch;
        _brands = brands;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _brands
        .where(
          (brand) => brand.name.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: ManagementTitle(
          '${_branch?.name ?? widget.branchName} inventory',
          subtitle: '${widget.fullName} · ${widget.role}',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
          ? Center(
              child: TextButton(
                onPressed: _load,
                child: const Text('Could not load inventory. Retry'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search brands',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Brands (${visible.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('No brands found'),
                  ),
                for (final brand in visible)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(brand.name),
                        subtitle: brand.description.isEmpty
                            ? null
                            : Text(brand.description),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BrandInventoryPage(
                              brandName: brand.name,
                              brandId: brand.id,
                              fullName: widget.fullName,
                              role: widget.role,
                              userId: widget.userId,
                              branchManager: widget.fullName,
                              branchCode: _branch!.id,
                              branchName: _branch!.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
