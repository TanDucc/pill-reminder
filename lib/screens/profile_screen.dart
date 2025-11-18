// dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? name;
  String? email;
  String? role;
  String? medicalCondition;
  DateTime? dob;
  String? gender;
  bool _loading = true;
  bool _noUser = false; // new: indicate not authenticated
  

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _noUser = false;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Not signed in: stop spinner and show login prompt
      setState(() {
        _loading = false;
        _noUser = true;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          name = data['name'] as String? ?? '';
          email = data['email'] as String? ?? user.email ?? '';
          role = data['role'] as String? ?? 'user';
          medicalCondition = data['medicalCondition'] as String? ?? '';
          gender = data['gender'] as String? ?? '';
          final ts = data['dob'];
          if (ts is Timestamp) {
            dob = ts.toDate();
          } else if (ts is String) {
            // attempt parse
            dob = DateTime.tryParse(ts);
          }
        });
      } else {
        setState(() {
          name = user.displayName ?? '';
          email = user.email ?? '';
          role = 'user';
          gender = '';

        });
      }
    } catch (e) {
      // Show error and allow retry
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể tải hồ sơ: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_noUser) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Bạn chưa đăng nhập.'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: const Text('Đến trang đăng nhập'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            const CircleAvatar(
              radius: 50,
              backgroundColor: Colors.blue,
              child: Icon(
                Icons.person,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              name ?? 'Không có tên',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(email ?? ''),
            const SizedBox(height: 30),
            _buildInfoCard('Vai trò', role ?? 'user'),
            const SizedBox(height: 12),
            _buildInfoCard('Ngày sinh', dob != null ? '${dob!.day.toString().padLeft(2, '0')}/${dob!.month.toString().padLeft(2, '0')}/${dob!.year}' : 'Không có'),
            const SizedBox(height: 12),
            _buildInfoCard('Bệnh lí', medicalCondition ?? 'Không có'),
            const SizedBox(height: 12),
            _buildInfoCard('Giới tính', gender ?? 'Không có'),
            const SizedBox(height: 24),

            const Spacer(),
            ElevatedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Text(
              '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
