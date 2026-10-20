import 'branch_inventory_screen.dart';

/// Compatibility route for the existing branch name.
class JasaanInventory extends BranchInventoryScreen {
  const JasaanInventory({
    super.key,
    required super.fullName,
    required super.role,
    required super.userId,
    required super.location,
  }) : super(branchName: 'JASAAN BRANCH');
}
