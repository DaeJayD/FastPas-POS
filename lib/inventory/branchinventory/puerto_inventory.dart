import 'branch_inventory_screen.dart';

/// Compatibility route for the existing branch name.
class PuertoInventory extends BranchInventoryScreen {
  const PuertoInventory({
    super.key,
    required super.fullName,
    required super.role,
    required super.userId,
    required super.location,
  }) : super(branchName: 'PUERTO BRANCH');
}
