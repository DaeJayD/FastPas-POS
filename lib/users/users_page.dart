import 'package:vasenizzpos/core/management_ui.dart';
import 'package:vasenizzpos/core/store_connection.dart';
import 'package:vasenizzpos/core/fastpas_theme.dart';
import 'package:flutter/material.dart';
import 'package:vasenizzpos/core/store_navigation.dart';

import '../employees/emp_profile.dart';

class UsersPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final int initialIndex;

  const UsersPage({
    super.key,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.initialIndex = 4,
  });

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, dynamic>> employees = [];
  List<Map<String, dynamic>> branches = [];

  TextEditingController nameController = TextEditingController();
  TextEditingController phoneController = TextEditingController();
  TextEditingController dobController = TextEditingController();
  TextEditingController usernameController = TextEditingController();

  String? selectedBranch;
  String? selectedRole;

  bool showEmployeeList = false;

  @override
  void initState() {
    super.initState();
    _fetchEmployees();
    _fetchBranches();
  }

  Future<void> _fetchBranches() async {
    try {
      final response = await StoreConnection.client
          .from('branches')
          .select('location')
          .order('location');

      if (response.isNotEmpty) {
        setState(() {
          branches = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint("Error fetching branches: $e");
    }
  }

  Future<String> _generateuserId() async {
    try {
      final response = await StoreConnection.client
          .from('employees')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1)
          .select();

      if (response.isNotEmpty) {
        String lastId = response[0]['user_id'];
        int number = int.parse(lastId.substring(1));
        return 'E${(number + 1).toString().padLeft(3, '0')}';
      } else {
        return 'E001';
      }
    } catch (e) {
      debugPrint('Error generating user_id: $e');
      return 'E001';
    }
  }

  Future<void> _createUser() async {
    final userId = await _generateuserId();
    if (!mounted) return;
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();
    final dob = dobController.text.trim();
    final username = usernameController.text.trim();

    if (name.isEmpty ||
        phone.isEmpty ||
        dob.isEmpty ||
        username.isEmpty ||
        selectedBranch == null ||
        selectedRole == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields.')));
      return;
    }

    try {
      final response = await StoreConnection.client.from('employees').insert({
        'name': name,
        'phone': phone,
        'dob': dob,
        'username': username,
        'user_id': userId,
        'branch': selectedBranch,
        'role': selectedRole,
        'password': '1',
      }).select();

      if (!mounted) return;
      if (response.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User $userId created successfully!')),
        );

        _fetchEmployees();
        nameController.clear();
        phoneController.clear();
        dobController.clear();
        usernameController.clear();

        setState(() {
          selectedBranch = null;
          selectedRole = null;
        });
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error creating user.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _fetchEmployees() async {
    try {
      final response = await StoreConnection.client.from('employees').select();

      setState(() {
        employees = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Error fetching employees: $e');
      setState(() => employees = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Volt.background,
      appBar: AppBar(
        title: ManagementTitle(
          'Staff',
          subtitle: '${widget.fullName} · ${widget.role}',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchEmployees();
              _fetchBranches();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => DraggableScrollableSheet(
                      initialChildSize: 0.5,
                      minChildSize: 0.3,
                      maxChildSize: 0.9,
                      expand: false,
                      builder: (context, scrollController) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                            ),
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 10),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              const Text(
                                "Employee List",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: employees.isEmpty
                                    ? const Center(
                                        child: Text("No employees found"),
                                      )
                                    : ListView.builder(
                                        controller: scrollController,
                                        itemCount: employees.length,
                                        itemBuilder: (context, index) {
                                          final employee = employees[index];
                                          return Container(
                                            margin: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[50],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        employee['name'] ?? '',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        "${employee['user_id']}  ${employee['role']}",
                                                        style: const TextStyle(
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        employee['phone'] ?? '',
                                                        style: const TextStyle(
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            EmployeeProfilePage(
                                                              userName:
                                                                  employee['name'],
                                                              userId:
                                                                  employee['user_id'],
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    color: Colors.redAccent,
                                                    size: 18,
                                                  ),
                                                  label: const Text(
                                                    "Edit",
                                                    style: TextStyle(
                                                      color: Colors.redAccent,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
                child: const Text(
                  "MANAGE USERS",
                  style: TextStyle(
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Create New User",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  buildTextField(
                    "Name",
                    "Employee Name",
                    controller: nameController,
                  ),
                  buildTextField(
                    "Phone Number",
                    "Ex. 09123456789",
                    controller: phoneController,
                  ),
                  buildTextField(
                    "Date of Birth",
                    "yyyy/mm/dd",
                    controller: dobController,
                  ),
                  buildTextField(
                    "Username",
                    "Username",
                    controller: usernameController,
                  ),
                  const SizedBox(height: 8),
                  ManagementColumns(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: selectedBranch,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          hint: const Text("Assign Branch"),
                          items: branches.map<DropdownMenuItem<String>>((
                            branch,
                          ) {
                            final String loc =
                                branch['location']?.toString() ?? "";
                            return DropdownMenuItem(
                              value: loc,
                              child: Text(loc),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedBranch = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          hint: const Text("Assign Role"),
                          items: ["Cashier", "Staff", "Manager"]
                              .map(
                                (val) => DropdownMenuItem(
                                  value: val,
                                  child: Text(val),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setState(() {
                              selectedRole = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Volt.lime,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _createUser,
                    icon: const Icon(Icons.add, color: Volt.ink),
                    label: const Text(
                      "Create User",
                      style: TextStyle(
                        color: Volt.ink,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!StoreConnection.isPreview)
              Center(
                child: TextButton(
                  onPressed: () => StoreNavigation.signOut(context),
                  child: const Text(
                    "Log Out",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: null,
    );
  }

  static Widget buildTextField(
    String label,
    String hint, {
    TextEditingController? controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}
