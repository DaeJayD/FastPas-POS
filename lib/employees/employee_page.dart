import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:vasenizzpos/main.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:vasenizzpos/services/gps_validator.dart';
import 'package:geolocator/geolocator.dart';

class UserProfileScreen extends StatefulWidget {
  final String fullName;
  final String role;
  final String userId;

  const UserProfileScreen({
    required this.fullName,
    required this.role,
    required this.userId,
    Key? key,
  }) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  bool _loading = false;
  Map<String, dynamic>? _employee;
  List<Map<String, dynamic>> _attendanceHistory = [];
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String _status = "Off Duty";
  bool _hasTimedInToday = false;

  @override
  void initState() {
    super.initState();
    _loadEmployeeInfo();
    _loadAttendanceHistory();
  }

  Future<void> _loadEmployeeInfo() async {
    try {
      final data = await supabase
          .from('employees')
          .select()
          .eq('user_id', widget.userId)
          .maybeSingle();

      if (data == null) return;

      setState(() => _employee = Map<String, dynamic>.from(data));
    } catch (e) {
      print('Error fetching employee: $e');
    }
  }

  Future<void> _loadAttendanceHistory() async {
    try {
      final data = await supabase
          .from('attendance')
          .select()
          .eq('user_id', widget.userId)
          .order('date', ascending: false);

      setState(() {
        _attendanceHistory = List<Map<String, dynamic>>.from(data);
        _updateStatus();
        _checkTodayAttendance();
      });
    } catch (e) {
      print('Error fetching attendance: $e');
    }
  }

  void _updateStatus() {
    if (_attendanceHistory.isEmpty) {
      _status = "Off Duty";
      return;
    }

    final today = DateTime.now().toIso8601String().split('T')[0];
    final todayEntry = _attendanceHistory.firstWhere(
          (entry) => entry['date'] == today,
      orElse: () => {},
    );

    if (todayEntry.isNotEmpty && todayEntry['time_out'] == null) {
      _status = "On Duty";
    } else {
      _status = "Off Duty";
    }
  }

  void _checkTodayAttendance() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final todayEntry = _attendanceHistory.firstWhere(
          (entry) => entry['date'] == today && entry['time_out'] == null,
      orElse: () => {},
    );

    _hasTimedInToday = todayEntry.isNotEmpty;
    print('_hasTimedInToday: $_hasTimedInToday, _status: $_status');
  }


  bool _isAttendanceDay(DateTime day) {
    return _attendanceHistory.any((entry) {
      final entryDate = DateTime.parse(entry['date']);
      return day.year == entryDate.year &&
          day.month == entryDate.month &&
          day.day == entryDate.day &&
          entry['time_out'] != null;
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() => _loading = true);

      try {
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);
        final imageUrl = 'data:image/jpeg;base64,$base64Image';

        await supabase
            .from('employees')
            .update({'profile_image': imageUrl})
            .eq('user_id', widget.userId);

        setState(() {
          _employee!['profile_image'] = imageUrl;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile picture updated successfully!')),
        );

      } catch (e) {
        print('Error processing image: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile picture: $e')),
        );
      } finally {
        setState(() => _loading = false);
      }
    }
  }

  final GPSValidator _gpsValidator = GPSValidator();

  Future<void> _timeIn() async {
    setState(() => _loading = true);
    final today = DateTime.now().toIso8601String().split('T')[0];

    try {
      print('DEBUG: Starting GPS validation for Time In...');

      // Validate location before allowing time in
      bool isAtStore = await _gpsValidator.isExactlyAtStore();

      if (!isAtStore) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ You must be at the store location to Time In'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        setState(() => _loading = false);
        return;
      }

      print('DEBUG: GPS validation passed, getting precise location...');

      // Get current location for recording
      final location = await _getCurrentLocation();
      if (location == null) {
        setState(() => _loading = false);
        return;
      }

      print('DEBUG: Inserting time in with location data...');
      await supabase.from('attendance').insert({
        'user_id': widget.userId,
        'time_in': DateTime.now().toIso8601String(),
        'date': today,
        'location_lat': location['latitude'],
        'location_long': location['longitude'],
        'location_accuracy': location['accuracy'],
      });

      setState(() {
        _status = "On Duty";
        _hasTimedInToday = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(' Time In successful! Location verified.'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('Time In error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Time In failed: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _timeOut() async {
    setState(() => _loading = true);
    final today = DateTime.now().toIso8601String().split('T')[0];

    try {
      print('DEBUG: Starting GPS validation for Time Out...');

      // Validate location before allowing time out
      bool isAtStore = await _gpsValidator.isExactlyAtStore();

      if (!isAtStore) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(' You must be at the store location to Time Out'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        setState(() => _loading = false);
        return;
      }

      print('DEBUG: GPS validation passed, getting precise location...');

      // Get current location for recording
      final location = await _getCurrentLocation();
      if (location == null) {
        setState(() => _loading = false);
        return;
      }

      print('DEBUG: Updating time out with location data...');
      await supabase.from('attendance').update({
        'time_out': DateTime.now().toIso8601String(),
        'time_out_lat': location['latitude'],
        'time_out_long': location['longitude'],
        'time_out_accuracy': location['accuracy'],
      }).eq('user_id', widget.userId).eq('date', today).filter('time_out', 'is', null);

      setState(() {
        _status = "Off Duty";
        _hasTimedInToday = false;
      });

      await _loadAttendanceHistory();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Time Out successful! Location verified.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Time Out error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Time Out failed: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

// Keep your existing _getCurrentLocation method for recording coordinates
  Future<Map<String, dynamic>?> _getCurrentLocation() async {
    try {
      print('DEBUG: Getting precise location for recording...');

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: Duration(seconds: 10),
      );

      print('DEBUG: Location acquired - Lat: ${position.latitude}, Long: ${position.longitude}');

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'timestamp': position.timestamp?.toIso8601String(),
      };
    } catch (e) {
      print('DEBUG: Location recording error: $e');
      return null;
    }
  }

  Widget _buildProfileImage() {
    final profileImage = _employee?['profile_image'];

    if (profileImage != null && profileImage.toString().startsWith('data:image')) {
      try {
        return ClipOval(
          child: Image.memory(
            base64Decode(profileImage.split(',').last),
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildDefaultProfile();
            },
          ),
        );
      } catch (e) {
        print('Error decoding base64 image: $e');
        return _buildDefaultProfile();
      }
    }

    return _buildDefaultProfile();
  }

  Widget _buildDefaultProfile() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFF8BBD0), Color(0xFFEC407A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.person, size: 40, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFCE4EC),
      appBar: AppBar(
        backgroundColor: Colors.pink.shade200,
        title: Text('Profile Page', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => VasenizzApp()),
                      (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: _employee == null
          ? Center(child: CircularProgressIndicator(color: Color(0xFFEC407A)))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // User info card
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    InkWell(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          _buildProfileImage(),
                          if (_loading)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black54,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(color: Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _employee!['name'] ?? '',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF880E4F),
                            ),
                          ),
                          SizedBox(height: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _status == "On Duty" ? Color(0xFFE8F5E8) : Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "Status: $_status",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _status == "On Duty" ? Color(0xFF2E7D32) : Color(0xFFD32F2F),
                              ),
                            ),
                          ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gps_fixed, size: 12, color: Colors.blue),
                            SizedBox(width: 4),
                            Text(
                              "GPS Required",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _loading || _hasTimedInToday ? null : _timeIn,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF4CAF50),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: _loading
                                      ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                      : Text('Time In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _loading || !_hasTimedInToday || _status == "Off Duty" ? null : _timeOut,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFFF44336),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  child: _loading
                                      ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                                      : Text('Time Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Attendance calendar
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Attendance Calendar",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF880E4F),
                      ),
                    ),
                    SizedBox(height: 16),
                    TableCalendar(
                      firstDay: DateTime.utc(2024, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      daysOfWeekVisible: false,
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: Color(0xFFF8BBD0).withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: Color(0xFFEC407A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          if (_isAttendanceDay(day)) {
                            return Container(
                              margin: const EdgeInsets.all(4),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFEC407A),
                              ),
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Attendance history
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Attendance History",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF880E4F),
                      ),
                    ),
                    SizedBox(height: 12),
                    ..._attendanceHistory.where((entry) => entry['time_out'] != null).map((entry) {
                      final timeIn = entry['time_in'] != null ? DateTime.parse(entry['time_in']) : null;
                      final timeOut = entry['time_out'] != null ? DateTime.parse(entry['time_out']) : null;

                      return Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color(0xFFFCE4EC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Color(0xFFF8BBD0)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: Color(0xFFEC407A), size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry['date'],
                                style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF880E4F)),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Color(0xFFE8F5E8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "In: ${timeIn != null ? "${timeIn.hour}:${timeIn.minute.toString().padLeft(2, '0')}" : "N/A"}",
                                style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
                              ),
                            ),
                            SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "Out: ${timeOut != null ? "${timeOut.hour}:${timeOut.minute.toString().padLeft(2, '0')}" : "N/A"}",
                                style: TextStyle(fontSize: 12, color: Color(0xFFD32F2F)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Employee info
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Personal Information",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF880E4F),
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildInfoField('Name', _employee!['name'] ?? ''),
                    SizedBox(height: 12),
                    _buildInfoField('Employee ID', _employee!['user_id'] ?? ''),
                    SizedBox(height: 12),
                    _buildInfoField('Phone Number', _employee!['phone'] ?? ''),
                    SizedBox(height: 12),
                    _buildInfoField('Branch Assigned', _employee!['branch'] ?? ''),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(0xFFFCE4EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFF8BBD0)),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF880E4F),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'Not provided',
              style: TextStyle(color: Color(0xFFEC407A)),
            ),
          ),
        ],
      ),
    );
  }
}