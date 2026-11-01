import '../core/receipt_details.dart';

class BusinessDetails {
  const BusinessDetails({
    required this.id,
    required this.name,
    required this.version,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.footer = '',
  });
  final String id, name, address, phone, email, footer;
  final int version;

  factory BusinessDetails.fromJson(Map<String, dynamic> json) =>
      BusinessDetails(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['settings_version'] as int,
        address: json['address'] as String,
        phone: json['contact_phone'] as String,
        email: json['contact_email'] as String,
        footer: json['receipt_footer'] as String,
      );

  ReceiptDetails receiptFor(BranchDetails branch) => ReceiptDetails(
    businessId: id,
    branchId: branch.id,
    businessName: name,
    branchName: branch.name,
    businessAddress: address,
    branchAddress: branch.address,
    phone: phone,
    email: email,
    footer: footer,
  );
}

class BranchDetails {
  const BranchDetails({
    required this.id,
    required this.businessId,
    required this.name,
    required this.version,
    this.address = '',
  });
  final String id, businessId, name, address;
  final int version;

  factory BranchDetails.fromJson(Map<String, dynamic> json) => BranchDetails(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    version: json['settings_version'] as int,
  );
}

class BusinessSettings {
  const BusinessSettings(this.business, this.branches);
  final BusinessDetails business;
  final List<BranchDetails> branches;

  factory BusinessSettings.fromJson(Map<String, dynamic> json) {
    final business = BusinessDetails.fromJson(
      Map<String, dynamic>.from(json['business'] as Map),
    );
    final branches = (json['branches'] as List)
        .map((b) => BranchDetails.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();
    if (branches.any((branch) => branch.businessId != business.id)) {
      throw StateError('Branch does not belong to this business.');
    }
    return BusinessSettings(business, List.unmodifiable(branches));
  }
}
