import 'package:flutter/material.dart';
import 'package:vasenizzpos/dashboard/home_screen.dart';
import 'package:vasenizzpos/main.dart';
import '../employees/emp_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vasenizzpos/sales/sales_screen.dart';
import 'package:vasenizzpos/inventory/inventory_screen.dart';
import 'package:vasenizzpos/reports/reports_page.dart';

class UsersPage extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;
  final String location;
  final int initialIndex;

  const UsersPage({
    Key? key,
    required this.fullName,
    required this.role,
    required this.userId,
    required this.location,
    this.initialIndex = 4,
  }) : super(key: key);

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  int _selectedIndex = 4;

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
      final response = await Supabase.instance.client
          .from('branches')
          .select('location')
          .order('location');

      if (response != null && response.isNotEmpty) {
        setState(() {
          branches = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print("Error fetching branches: $e");
    }
  }

  Future<String> _generateuserId() async {
    try {
      final response = await Supabase.instance.client
          .from('employees')
          .select('user_id')
          .order('user_id', ascending: false)
          .limit(1)
          .select();

      if (response != null && response.isNotEmpty) {
        String lastId = response[0]['user_id'];
        int number = int.parse(lastId.substring(1));
        return 'E${(number + 1).toString().padLeft(3, '0')}';
      } else {
        return 'E001';
      }
    } catch (e) {
      print('Error generating user_id: $e');
      return 'E001';
    }
  }

  Future<void> _createUser() async {
    final userId = await _generateuserId();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields.')),
      );
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('employees')
          .insert({
        'name': name,
        'phone': phone,
        'dob': dob,
        'username': username,
        'user_id': userId,
        'branch': selectedBranch,
        'role': selectedRole,
        'password': '1',
      }).select();

      if (response != null && response.isNotEmpty) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error creating user.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _fetchEmployees() async {
    try {
      final response = await Supabase.instance.client.from('employees').select();

      setState(() {
        employees = response != null
            ? List<Map<String, dynamic>>.from(response)
            : [];
      });
    } catch (e) {
      print('Error fetching employees: $e');
      setState(() => employees = []);
    }
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    Widget nextPage;
    switch (index) {
      case 0:
        nextPage = HomeScreen(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 0,
        );
        break;
      case 1:
        nextPage = SalesScreen(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 1,
        );
        break;
      case 2:
        nextPage = InventoryPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 2,
        );
        break;
      case 3:
        nextPage = ViewReportsPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 3,
        );
        break;
      case 4:
        nextPage = UsersPage(
          fullName: widget.fullName,
          role: widget.role,
          userId: widget.userId,
          location: widget.location,
          initialIndex: 4,
        );
        break;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => nextPage,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFF5C6D3),
        elevation: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 25,
              backgroundImage: AssetImage('assets/logo.png'),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Manage Users",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.black87),
                ),
                Text(
                  "${widget.fullName} (${widget.role})",
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 15),
            child: Icon(Icons.notifications_none,
                color: Colors.black54, size: 26),
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
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
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
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                              ),
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
                                    color: Colors.black87),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: employees.isEmpty
                                    ? const Center(child: Text("No employees found"))
                                    : ListView.builder(
                                  controller: scrollController,
                                  itemCount: employees.length,
                                  itemBuilder: (context, index) {
                                    final employee = employees[index];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[50],
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                              children: [
                                                Text(employee['name'] ?? '',
                                                    style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16)),
                                                const SizedBox(height: 2),
                                                Text(
                                                    "${employee['user_id']}  ${employee['role']}",
                                                    style: const TextStyle(
                                                        color: Colors.black54)),
                                                const SizedBox(height: 2),
                                                Text(employee['phone'] ?? '',
                                                    style: const TextStyle(
                                                        color: Colors.black54)),
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
                                                        userName: employee['name'],
                                                        userId: employee['user_id'],
                                                      ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.edit,
                                                color: Colors.redAccent, size: 18),
                                            label: const Text(
                                              "Edit",
                                              style: TextStyle(color: Colors.redAccent),
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
                      color: Colors.white),
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "Create New User",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black87),
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
                  buildTextField("Name", "Employee Name",
                      controller: nameController),
                  buildTextField("Phone Number", "Ex. 09123456789",
                      controller: phoneController),
                  buildTextField("Date of Birth", "yyyy/mm/dd",
                      controller: dobController),
                  buildTextField("Username", "Username",
                      controller: usernameController),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: DropdownButtonFormField<String>(
                          value: selectedBranch,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          hint: const Text("Assign Branch"),

                          items: branches
                              .map<DropdownMenuItem<String>>((branch) {
                            final String loc =
                                branch['location']?.toString() ?? "";
                            return DropdownMenuItem(
                                value: loc, child: Text(loc));
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
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          hint: const Text("Assign Role"),

                          items: ["Cashier", "Staff", "Manager"]
                              .map((val) => DropdownMenuItem(
                            value: val,
                            child: Text(val),
                          ))
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
                      backgroundColor: Colors.greenAccent.shade100,
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _createUser,
                    icon: const Icon(Icons.add, color: Colors.green),
                    label: const Text(
                      "Create User",
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => VasenizzApp()),
                          (route) => false);
                },
                child: const Text(
                  "Log Out",
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.pink,
        unselectedItemColor: Colors.black54,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded), label: "Dashboard"),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart), label: "Sales"),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory), label: "Inventory"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Report"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }

  static Widget buildTextField(String label, String hint,
      {TextEditingController? controller}) {
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
