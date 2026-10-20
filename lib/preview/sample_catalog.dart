import '../catalog/catalog_source.dart';

/// Explicit UI fixtures. Production startup never selects this source.
class SampleCatalog extends CatalogSource {
  @override
  bool get isPreview => true;

  @override
  Future<List<StoreBranch>> branches({
    required String userId,
    required String role,
    required String location,
  }) async => const [
    StoreBranch(
      id: 'sample-main',
      name: 'Main Branch',
      location: 'Main Branch',
    ),
    StoreBranch(
      id: 'sample-north',
      name: 'North Branch',
      location: 'North Branch',
    ),
  ];

  @override
  Future<List<CatalogProduct>> products(String branchId) async => const [
    CatalogProduct(
      id: 'water',
      name: 'Bottled Water',
      price: 25,
      stock: 48,
      sku: 'DR-001',
      category: 'Drinks',
    ),
    CatalogProduct(
      id: 'cookies',
      name: 'Butter Cookies',
      price: 65,
      stock: 24,
      sku: 'FD-001',
      category: 'Food',
    ),
    CatalogProduct(
      id: 'coffee',
      name: 'Instant Coffee',
      price: 15,
      stock: 60,
      sku: 'DR-002',
      category: 'Drinks',
    ),
    CatalogProduct(
      id: 'soap',
      name: 'Bath Soap',
      price: 45,
      stock: 32,
      sku: 'ES-001',
      category: 'Essentials',
    ),
    CatalogProduct(
      id: 'tissue',
      name: 'Pocket Tissue',
      price: 20,
      stock: 4,
      sku: 'ES-002',
      category: 'Essentials',
    ),
    CatalogProduct(
      id: 'pen',
      name: 'Ballpoint Pen',
      price: 12,
      stock: 36,
      sku: 'ST-001',
      category: 'Stationery',
    ),
    CatalogProduct(
      id: 'notebook',
      name: 'Everyday Notebook',
      price: 55,
      stock: 0,
      sku: 'ST-002',
      category: 'Stationery',
    ),
    CatalogProduct(
      id: 'snacks',
      name: 'Classic Salted Crackers',
      price: 30,
      stock: 16,
      sku: 'FD-002',
      category: 'Food',
    ),
  ];
}
