import 'branch_screen.dart';

/// Compatibility route for the existing branch name.
class CarmenScreen extends BranchScreen {
  const CarmenScreen({
    super.key,
    required super.fullName,
    required super.role,
    required super.userId,
    required super.location,
  }) : super(branchName: 'CARMEN BRANCH');
}
