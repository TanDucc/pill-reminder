import 'dart:convert'; // [MỚI] Để dùng jsonEncode
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart'; // [MỚI] Để lấy User ID

class WifiConfigScreen extends StatefulWidget {
  const WifiConfigScreen({super.key});

  @override
  State<WifiConfigScreen> createState() => _WifiConfigScreenState();
}

class _WifiConfigScreenState extends State<WifiConfigScreen> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _sendWifiConfig() async {
    // 1. Kiểm tra nhập liệu
    if (_ssidController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng nhập đầy đủ SSID và Password!')),
      );
      return;
    }

    // 2. Lấy User ID từ Firebase
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Bạn chưa đăng nhập! Vui lòng đăng nhập lại.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 3. Chuẩn bị dữ liệu JSON
      // Lưu ý: Các Key "ssid", "pass", "uid" phải khớp với code trên ESP32
      final Map<String, dynamic> data = {
        'ssid': _ssidController.text.trim(),
        'pass': _passwordController.text.trim(), // Đổi key thành 'pass' cho gọn
        'uid': user.uid, // [QUAN TRỌNG] Gửi kèm User ID để ESP32 lưu lại
      };

      print("Đang gửi cấu hình: $data");

      // 4. Gửi Request tới ESP32 (IP mặc định AP là 192.168.4.1)
      final uri = Uri.parse('http://192.168.4.1/config');
      
      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json", // Báo cho ESP biết đây là JSON
        },
        body: jsonEncode(data), // Chuyển Map sang chuỗi JSON
      ).timeout(const Duration(seconds: 10)); // Tăng timeout lên xíu cho chắc

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Gửi cấu hình thành công! ESP32 đang khởi động lại...')),
        );
        // Có thể pop màn hình này ra sau khi thành công
        // Navigator.pop(context); 
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi từ ESP32 (${response.statusCode}): ${response.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Không kết nối được với ESP32. Hãy chắc chắn bạn đã kết nối vào Wifi của hộp thuốc!\nLỗi: $e')),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình Thiết bị mới')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView( // Thêm SingleChildScrollView để không bị che khi bàn phím hiện
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.router, size: 80, color: Colors.blue),
              const SizedBox(height: 20),
              const Text(
                'Bước 1: Kết nối điện thoại vào Wifi "ESP_Setup"',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              const Text(
                'Bước 2: Nhập Wifi nhà bạn để thiết bị kết nối',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              
              TextField(
                controller: _ssidController,
                decoration: const InputDecoration(
                  labelText: 'Tên Wifi (SSID)',
                  prefixIcon: Icon(Icons.wifi),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu Wifi',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                obscureText: true, // Ẩn mật khẩu
              ),
              
              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        onPressed: _sendWifiConfig,
                        icon: const Icon(Icons.send),
                        label: const Text('GỬI CẤU HÌNH'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}