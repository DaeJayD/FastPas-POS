import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmployeeProfilePage extends StatefulWidget {
  final String userId;
  final String userName;

  const EmployeeProfilePage({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> {
  Map<String, dynamic>? employeeData;
  final SupabaseClient _supabase = Supabase.instance.client;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController dobController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController branchController = TextEditingController();
  final TextEditingController roleController = TextEditingController();

  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchEmployee();
  }

  Future<void> _fetchEmployee() async {
    try {
      print('Fetching employee with user_id: ${widget.userId}');

      final response = await _supabase
          .from('employees')
          .select()
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (response != null) {
        setState(() {
          employeeData = Map<String, dynamic>.from(response);
          nameController.text = employeeData!['name']?.toString() ?? '';
          phoneController.text = employeeData!['phone']?.toString() ?? '';
          dobController.text = _formatDate(employeeData!['dob']);
          usernameController.text = employeeData!['username']?.toString() ?? '';
          branchController.text = employeeData!['branch']?.toString() ?? '';
          roleController.text = employeeData!['role']?.toString() ?? '';
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'Employee not found';
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching employee: $e');
      setState(() {
        errorMessage = 'Error loading employee data';
        isLoading = false;
      });
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    if (date is DateTime) return date.toIso8601String().split('T')[0];
    if (date is String) {
      try {
        return DateTime.parse(date).toIso8601String().split('T')[0];
      } catch (e) {
        return date;
      }
    }
    return date.toString();
  }

  Future<void> _updateEmployee() async {
    try {
      final updates = {
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'dob': dobController.text.trim().isNotEmpty ? dobController.text.trim() : null,
        'username': usernameController.text.trim(),
        'branch': branchController.text.trim(),
        'role': roleController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase
          .from('employees')
          .update(updates)
          .eq('user_id', widget.userId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Employee updated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      await _fetchEmployee();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating employee: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteEmployee() async {
    bool confirmDelete = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Deactivate Employee"),
        content: Text("Are you sure you want to deactivate ${nameController.text}? They will no longer be able to access the system."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Deactivate", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirmDelete) return;

    try {
      await _supabase
          .from('employees')
          .update({
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', widget.userId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Employee deactivated successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deactivating employee: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8EDF3),
      appBar: AppBar(
        backgroundColor: Color(0xFFF5C6D3),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Employee Profile",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            onPressed: _fetchEmployee,
          ),
        ],
      ),
      body: isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading employee data...',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      )
          : errorMessage.isNotEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              errorMessage,
              style: const TextStyle(fontSize: 16, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchEmployee,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFA0C0),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFFF8EDF3),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFA0C0),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 40,
                      color: Color(0xFFFF6B8A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    employeeData!['name'] ?? 'No Name',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    employeeData!['role']?.toString().toUpperCase() ?? 'NO ROLE',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'User ID: ${widget.userId}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Employee Details Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Color(0xFFF5C6D3),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Employee Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Divider(color: Colors.grey, height: 24),
                  const SizedBox(height: 8),

                  _buildInfoField("Full Name", nameController, Icons.person_outline),
                  _buildInfoField("Phone Number", phoneController, Icons.phone_iphone),
                  _buildInfoField("Date of Birth", dobController, Icons.calendar_today),
                  _buildInfoField("Username", usernameController, Icons.alternate_email),
                  _buildInfoField("Branch", branchController, Icons.business),
                  _buildInfoField("Role", roleController, Icons.work_outline),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _deleteEmployee,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Color(0xFFFF6B8A)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_off, color: Color(0xFFFF6B8A), size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Deactivate",
                          style: TextStyle(
                            color: Color(0xFFFF6B8A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _updateEmployee,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8A),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Save Changes",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoField(String label, TextEditingController controller, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                color: const Color(0xFFFF6B8A),
                size: 20,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFFF6B8A)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              fillColor: Colors.grey[50],
              filled: true,
            ),
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
