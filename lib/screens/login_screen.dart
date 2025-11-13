import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  final _formKey = GlobalKey<FormState>();

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập email và mật khẩu!')),
      );
      return;
    }
    setState(() { _isLoading = true; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đăng nhập thành công!')),
        );
        Navigator.pushReplacementNamed(context, '/main');
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Đăng nhập thất bại';
      if (e.code == 'user-not-found') {
        message = 'Không tìm thấy tài khoản.';
      } else if (e.code == 'wrong-password') {
        message = 'Mật khẩu không đúng.';
      } else if (e.code == 'invalid-email') {
        message = 'Email không hợp lệ.';
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
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  void _togglePassword() {
    setState(() { _obscurePassword = !_obscurePassword; });
  }

  void _forgotPassword() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập email để lấy lại mật khẩu')));
      return;
    }
    FirebaseAuth.instance.sendPasswordResetEmail(email: email).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi email đặt lại mật khẩu.')));
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể gửi email: $e')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle),
                    child: const CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.medication, size: 40, color: Color(0xFF1E88E5)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Pill Reminder', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.email),
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập email' : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.lock),
                                labelText: 'Mật khẩu',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off), onPressed: _togglePassword),
                              ),
                              validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng nhập mật khẩu' : null,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Checkbox(value: _rememberMe, onChanged: (v) { setState(() { _rememberMe = v ?? false; }); }),
                                const Text('Ghi nhớ đăng nhập'),
                                const Spacer(),
                                TextButton(onPressed: _forgotPassword, child: const Text('Quên mật khẩu?')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Đăng nhập', style: TextStyle(fontSize: 16)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Chưa có tài khoản?'),
                                TextButton(onPressed: () { Navigator.pushNamed(context, '/register'); }, child: const Text('Đăng ký')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}