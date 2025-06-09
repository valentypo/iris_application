import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'login_page.dart';
import 'object_detection.dart';
import 'text_detection_page.dart';
import 'package:camera/camera.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class Reminder {
  final String type;
  final TimeOfDay time;
  final String description;

  Reminder({required this.type, required this.time, required this.description});

  Map<String, dynamic> toJson() => {
    'type': type,
    'hour': time.hour,
    'minute': time.minute,
    'description': description,
  };

  static Reminder fromJson(Map<String, dynamic> json) => Reminder(
    type: json['type'],
    time: TimeOfDay(hour: json['hour'], minute: json['minute']),
    description: json['description'],
  );
}

class HomePage extends StatefulWidget {
  final String email;
  final String? username;
  final List<CameraDescription>
  cameras; // Move cameras to constructor parameters

  const HomePage({
    super.key,
    required this.email,
    this.username,
    required this.cameras, // Make cameras required
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Reminder> reminders = [];
  String? lastSavedDate;

  String? _contactName;
  String? _contactPhone;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month}-${today.day}";
    lastSavedDate = prefs.getString('reminders_date');
    if (lastSavedDate == todayStr) {
      final remindersJson = prefs.getStringList('reminders') ?? [];
      setState(() {
        reminders =
            remindersJson
                .map((e) => Reminder.fromJson(json.decode(e)))
                .toList();
      });
    } else {
      // New day, clear reminders
      await prefs.setString('reminders_date', todayStr);
      await prefs.setStringList('reminders', []);
      setState(() {
        reminders = [];
      });
    }
  }

  Future<void> _saveReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month}-${today.day}";
    await prefs.setString('reminders_date', todayStr);
    await prefs.setStringList(
      'reminders',
      reminders.map((r) => json.encode(r.toJson())).toList(),
    );
  }

  Future<void> _clearReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reminders');
    await prefs.remove('reminders_date');
    setState(() {
      reminders = [];
    });
  }

  Future<void> _showAddReminderDialog() async {
    final _typeController = TextEditingController();
    final _descController = TextEditingController();
    TimeOfDay? selectedTime;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text('Add a Reminder'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _typeController,
                          decoration: InputDecoration(
                            labelText: 'Reminder Type',
                          ),
                        ),
                        SizedBox(height: 10),
                        TextField(
                          controller: _descController,
                          decoration: InputDecoration(labelText: 'Description'),
                        ),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              selectedTime == null
                                  ? 'Select Time'
                                  : selectedTime!.format(context),
                            ),
                            Spacer(),
                            TextButton(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.now(),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    selectedTime = picked;
                                  });
                                }
                              },
                              child: Text('Pick Time'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (_typeController.text.isNotEmpty &&
                            _descController.text.isNotEmpty &&
                            selectedTime != null &&
                            reminders.length < 5) {
                          setState(() {
                            reminders.add(
                              Reminder(
                                type: _typeController.text,
                                time: selectedTime!,
                                description: _descController.text,
                              ),
                            );
                          });
                          await _saveReminders();
                          Navigator.of(context).pop();
                        }
                      },
                      child: Text('Add'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _removeReminder(int index) async {
    setState(() {
      reminders.removeAt(index);
    });
    await _saveReminders();
  }

  // Add this function to show error dialogs
  Future<void> _showErrorDialog(String message) async {
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Error'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          ),
    );
  }

  // Update _pickContact to request permission and show dialog on error
  Future<void> _pickContact() async {
    final permission = await Permission.contacts.request();
    if (permission.isGranted) {
      final contact = await FlutterContacts.openExternalPick();
      if (contact != null && contact.phones.isNotEmpty) {
        setState(() {
          _contactName = contact.displayName;
          _contactPhone = contact.phones.first.number;
        });
        await showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text('Contact Added'),
                content: Text('Contact "${_contactName!}" added!'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('OK'),
                  ),
                ],
              ),
        );
      } else {
        await _showErrorDialog('No phone number found for this contact.');
      }
    } else {
      await _showErrorDialog('Contacts permission denied');
    }
  }

  // Update _callContact to request permission and show dialog on error
  Future<void> _callContact() async {
    if (_contactPhone == null) {
      await _showErrorDialog(
        'No contact selected. Please add a contact first.',
      );
      return;
    }
    final permission = await Permission.phone.request();
    if (permission.isGranted) {
      final Uri url = Uri(scheme: 'tel', path: _contactPhone);
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        await _showErrorDialog('Could not launch phone app');
      }
    } else {
      await _showErrorDialog('Phone call permission denied');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF234462),
      appBar: AppBar(
        backgroundColor: const Color(0xFF234462),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sign Out',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear(); // Clear all saved preferences
              await FirebaseAuth.instance.signOut();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            child: Column(
              children: [
                SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      "Hello",
                      style: TextStyle(color: Colors.white70, fontSize: 22),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      "${widget.username ?? 'User'}.",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "TODAY'S REMINDER",
                            style: TextStyle(
                              color: Color(0xFF234462),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 16),
                          reminders.isEmpty
                              ? Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(20),
                                margin: EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Color(0xFF234462),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Text(
                                  "No reminders yet.",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              )
                              : SizedBox(
                                height: 180,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: reminders.length,
                                  separatorBuilder:
                                      (_, __) => SizedBox(width: 16),
                                  itemBuilder: (context, index) {
                                    final reminder = reminders[index];
                                    return Dismissible(
                                      key: ValueKey(
                                        reminder.hashCode.toString() +
                                            index.toString(),
                                      ),
                                      direction: DismissDirection.up,
                                      onDismissed: (direction) {
                                        _removeReminder(index);
                                      },
                                      background: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.delete,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                      ),
                                      child: Container(
                                        width: 260,
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Color(0xFF234462),
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  reminder.type,
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.delete,
                                                    color: Colors.white70,
                                                    size: 20,
                                                  ),
                                                  onPressed:
                                                      () => _removeReminder(
                                                        index,
                                                      ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              reminder.time.format(context),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            SizedBox(height: 8),
                                            Flexible(
                                              child: Text(
                                                reminder.description,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          SizedBox(height: 8),
                          reminders.length < 5
                              ? SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF234462),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  onPressed: _showAddReminderDialog,
                                  child: Text("Add a Reminder"),
                                ),
                              )
                              : Container(),
                          SizedBox(height: 24),
                          Text(
                            "Need some help?",
                            style: TextStyle(
                              color: Color(0xFF234462),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 110,
                                  decoration: BoxDecoration(
                                    color: Color(0xFF234462),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: GestureDetector(
                                    onTap: () {
                                      // Check if cameras are available before navigating
                                      if (widget.cameras.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (context) => TextDetectionApp(
                                                  cameras: widget.cameras,
                                                ),
                                          ),
                                        );
                                      } else {
                                        // Show error message if no cameras available
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'No cameras available on this device',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.text_snippet,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "Text\nReader",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  height: 110,
                                  decoration: BoxDecoration(
                                    color: Color(0xFF234462),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: GestureDetector(
                                    // Add GestureDetector here
                                    onTap: () {
                                      // Check if cameras are available before navigating
                                      if (widget.cameras.isNotEmpty) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (context) => ObjectDetection(
                                                  cameras: widget.cameras,
                                                ),
                                          ),
                                        );
                                      } else {
                                        // Show error message if no cameras available
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'No cameras available on this device',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.search,
                                          color: Colors.white,
                                          size: 40,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "Object\nDetector",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red,
        onPressed: () async {
          if (_contactPhone == null) {
            await _pickContact();
          } else {
            await _callContact();
          }
        },
        child: Icon(Icons.phone, color: Colors.white),
        tooltip: _contactPhone == null ? 'Add Contact' : 'Call Contact',
      ),
    );
  }
}
