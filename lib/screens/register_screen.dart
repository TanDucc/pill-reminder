import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _medicalController = TextEditingController();
  bool _isLoading = false;
  DateTime? _selectedDob;

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final medical = _medicalController.text.trim();
    final dob = _selectedDob;
    if (email.isEmpty || password.isEmpty || name.isEmpty || dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập đầy đủ thông tin!')),
      );
      return;
    }
    setState(() { _isLoading = true; });
    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Lưu thông tin tài khoản vào Firestore
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        // authoritative role stays 'user'
        'role': 'user',
        // thêm thông tin cá nhân
        'dob': Timestamp.fromDate(dob),
        'medicalCondition': medical,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đăng ký thành công!')),
        );
        Navigator.pushReplacementNamed(context, '/main');
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Đăng ký thất bại';
      if (e.code == 'email-already-in-use') {
        message = 'Email đã được sử dụng.';
      } else if (e.code == 'invalid-email') {
        message = 'Email không hợp lệ.';
      } else if (e.code == 'weak-password') {
        message = 'Mật khẩu quá yếu (tối thiểu 6 ký tự).';
      } else {
        message = e.message ?? message;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi không xác định: $e')),
      );
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _selectedDob ?? DateTime(now.year - 30);
    final firstDate = DateTime(1900);
    final lastDate = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký tài khoản')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Họ và tên'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _dobController,
              decoration: const InputDecoration(labelText: 'Ngày sinh'),
              readOnly: true,
              onTap: _pickDob,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _medicalController,
              decoration: const InputDecoration(labelText: 'Bệnh lí (nếu có)'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Mật khẩu'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 8),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _register,
                    child: const Text('Đăng ký'),
                  ),
          ],
        ),
      ),
    );
  }
}