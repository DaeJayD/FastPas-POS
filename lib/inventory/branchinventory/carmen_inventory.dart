import 'branch_inventory_screen.dart';

/// Compatibility route for the existing branch name.
class CarmenInventory extends BranchInventoryScreen {
  const CarmenInventory({
    super.key,
    required super.fullName,
    required super.role,
    required super.userId,
    required super.location,
  }) : super(branchName: 'CARMEN BRANCH');
}
