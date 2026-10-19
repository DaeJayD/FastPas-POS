import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/inventory/brand_inventory.dart';

class BrandManagement {
  static void showBrandList({
    required BuildContext context,
    required List<dynamic> brands,
    required String fullName,
    required String role,
    required String branchManager,
    required String branchCode,
    required String branchName,
    required String userId,
    required Function() onBrandsUpdated,
  }) {
    showDialog(
      context: context,
      builder: (context) =>
          Dialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.pink[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Select Brand",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 300,
                    child: brands.isEmpty
                        ? const Center(child: Text('No brands available'))
                        : ListView.builder(
                      itemCount: brands.length,
                      itemBuilder: (context, index) {
                        final brand = brands[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 3)
                            ],
                          ),
                          child: ListTile(
                            title: Text(brand['name']),
                            subtitle: brand['description'] != null
                                ? Text(brand['description'])
                                : null,
                            trailing: const Icon(
                                Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      BrandInventoryPage(
                                        brandName: brand['name'],
                                        userId: userId,
                                        fullName: fullName,
                                        role: role,
                                        branchManager: branchManager,
                                        branchCode: branchCode,
                                        branchName: branchName,
                                      ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink[300],
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    child: const Text(
                        "CLOSE", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  static void showUpdateBrandPopup({
    required BuildContext context,
    required SupabaseClient supabase,
    required String branchId, // Add branchId parameter
    Map<String, dynamic>? existingBrand,
    required Function() onBrandsUpdated,
  }) {
    final TextEditingController brandNameController = TextEditingController(
        text: existingBrand?['name'] ?? ''
    );
    final TextEditingController brandDescController = TextEditingController(
        text: existingBrand?['description'] ?? ''
    );

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.pink[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    existingBrand != null
                        ? "Edit Brand"
                        : "Add Brand to Branch",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  // ... rest of your dialog UI ...
                  ElevatedButton(
                    onPressed: () async {
                      String name = brandNameController.text.trim();
                      String description = brandDescController.text.trim();

                      if (name.isNotEmpty) {
                        try {
                          String brandId;

                          if (existingBrand != null) {
                            // Update existing brand
                            await supabase
                                .from('brands')
                                .update({
                              'name': name,
                              'description': description.isEmpty
                                  ? null
                                  : description,
                            })
                                .eq('id', existingBrand['id']);
                            brandId = existingBrand['id'];
                          } else {
                            // Create new brand and add to branch
                            final result = await supabase
                                .from('brands')
                                .insert({
                              'name': name,
                              'description': description.isEmpty
                                  ? null
                                  : description,
                            })
                                .select();
                            brandId = result[0]['id'];

                            // Add to branch_brands junction table
                            await supabase
                                .from('branch_brands')
                                .insert({
                              'branch_id': branchId,
                              'brand_id': brandId,
                            });
                          }

                          onBrandsUpdated();
                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(
                                existingBrand != null
                                    ? 'Brand updated successfully'
                                    : 'Brand added to branch successfully'
                            )),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink[300],
                      minimumSize: const Size(double.infinity, 45),
                    ),
                    child: Text(
                        existingBrand != null ? "UPDATE" : "ADD TO BRANCH",
                        style: const TextStyle(color: Colors.white)
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static void showRemoveBrandPopup({
    required BuildContext context,
    required SupabaseClient supabase,
    required String branchId, // Add branchId parameter
    required List<dynamic> brands,
    required Function() onBrandsUpdated,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.pink[50],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Remove Brand from Branch",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 300,
                  child: brands.isEmpty
                      ? const Center(
                      child: Text('No brands available in this branch'))
                      : ListView.builder(
                    itemCount: brands.length,
                    itemBuilder: (context, index) {
                      final brand = brands[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 3)
                          ],
                        ),
                        child: ListTile(
                          title: Text(brand['name']),
                          subtitle: brand['description'] != null
                              ? Text(brand['description'])
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              bool confirm = await showDialog(
                                context: context,
                                builder: (context) =>
                                    AlertDialog(
                                      title: const Text("Confirm Remove"),
                                      content: Text(
                                        "Remove ${brand['name']} from this branch?",
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text("CANCEL"),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text("REMOVE",
                                              style: TextStyle(
                                                  color: Colors.red)),
                                        ),
                                      ],
                                    ),
                              );

                              if (confirm == true) {
                                try {
                                  // Remove from branch_brands (not delete the brand entirely)
                                  await supabase
                                      .from('branch_brands')
                                      .delete()
                                      .eq('branch_id', branchId)
                                      .eq('brand_id', brand['id']);

                                  onBrandsUpdated();
                                  Navigator.pop(context);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(
                                        '${brand['name']} removed from branch')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(
                                        'Error removing brand: $e')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink[300],
                    minimumSize: const Size(double.infinity, 45),
                  ),
                  child: const Text(
                      "CLOSE", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}