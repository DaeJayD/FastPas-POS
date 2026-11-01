/// Printable details copied into a sale; later edits never rewrite that sale.
class ReceiptDetails {
  const ReceiptDetails({
    required this.businessId,
    required this.branchId,
    required this.businessName,
    required this.branchName,
    this.businessAddress = '',
    this.branchAddress = '',
    this.phone = '',
    this.email = '',
    this.footer = '',
  });

  final String businessId, branchId, businessName, branchName;
  final String businessAddress, branchAddress, phone, email, footer;

  factory ReceiptDetails.fromRows(
    Map<String, dynamic> business,
    Map<String, dynamic> branch,
  ) => ReceiptDetails(
    businessId: business['id'] as String,
    branchId: branch['id'] as String,
    businessName: business['name'] as String,
    branchName: branch['name'] as String,
    businessAddress: business['address'] as String? ?? '',
    branchAddress: branch['address'] as String? ?? '',
    phone: business['contact_phone'] as String? ?? '',
    email: business['contact_email'] as String? ?? '',
    footer: business['receipt_footer'] as String? ?? '',
  );

  factory ReceiptDetails.fromJson(Map<String, dynamic> json) => ReceiptDetails(
    businessId: json['business_id'] as String,
    branchId: json['branch_id'] as String,
    businessName: json['business_name'] as String,
    branchName: json['branch_name'] as String,
    businessAddress: json['business_address'] as String? ?? '',
    branchAddress: json['branch_address'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    footer: json['footer'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'business_id': businessId,
    'branch_id': branchId,
    'business_name': businessName,
    'branch_name': branchName,
    'business_address': businessAddress,
    'branch_address': branchAddress,
    'phone': phone,
    'email': email,
    'footer': footer,
    'currency': 'PHP',
  };

  void checkScope(String business, String branch) {
    if (businessId != business || branchId != branch) {
      throw StateError('Receipt details do not belong to this store.');
    }
  }

  List<String> get heading => [
    businessName,
    branchName,
    if (branchAddress.isNotEmpty) branchAddress,
    if (businessAddress.isNotEmpty && businessAddress != branchAddress)
      businessAddress,
    if (phone.isNotEmpty) phone,
    if (email.isNotEmpty) email,
  ];
}
