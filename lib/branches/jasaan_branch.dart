import 'branch_screen.dart';

/// Compatibility route for the existing branch name.
class JasaanScreen extends BranchScreen {
  const JasaanScreen({
    super.key,
    required super.fullName,
    required super.role,
    required super.userId,
    required super.location,
  }) : super(branchName: 'JASAAN BRANCH');
}
