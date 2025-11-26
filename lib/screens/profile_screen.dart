// dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  final ValueNotifier<int>? selectedIndexNotifier;

  const ProfileScreen({required this.selectedIndexNotifier, super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? name;
  String? email;
  String? role;
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

  Future<void> _resetPassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy email để đặt lại mật khẩu')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email đặt lại mật khẩu đã được gửi')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi gửi email: $e')),
        );
      }
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
      appBar: AppBar(
        title: const Text('Thông tin cá nhân'),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: Colors.blue[200],
                    child: Icon(Icons.person, size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.wc, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(gender ?? '', style: const TextStyle(fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.cake, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(
                                dob != null ? '${dob!.day.toString().padLeft(2, '0')}/${dob!.month.toString().padLeft(2, '0')}/${dob!.year}' : '',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.email, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(email ?? 'Chưa đăng nhập', style: const TextStyle(fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.verified_user, color: Colors.teal),
                              const SizedBox(width: 8),
                              Text(FirebaseAuth.instance.currentUser?.uid ?? '', style: const TextStyle(fontSize: 16)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    color: Colors.blue[50],
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.medication, color: Colors.teal),
                            title: const Text('Lịch sử uống thuốc'),
                            subtitle: const Text('Xem lại các ngày đã uống thuốc'),
                            onTap: () => widget.selectedIndexNotifier?.value = 1,
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.settings, color: Colors.teal),
                            title: const Text('Cài đặt'),
                            subtitle: const Text('Tùy chỉnh ứng dụng'),
                            onTap: () {
                              // TODO: Chuyển sang màn hình cài đặt
                            },
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.lock_reset, color: Colors.teal),
                            title: const Text('Quên mật khẩu'),
                            subtitle: const Text('Gửi email đặt lại mật khẩu'),
                            onTap: _resetPassword,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushReplacementNamed('/login');
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Đăng xuất'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
