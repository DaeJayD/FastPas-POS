import 'branch_screen.dart';

/// Compatibility route for the existing branch name.
class PuertoScreen extends BranchScreen {
  const PuertoScreen({
    super.key,
    required super.fullName,
    required super.role,
    required super.userId,
    required super.location,
  }) : super(branchName: 'PUERTO BRANCH');
}
