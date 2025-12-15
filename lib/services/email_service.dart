import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailService {
  // 1. THAY THẾ CÁC MÃ CỦA BẠN VÀO ĐÂY
  final String _serviceId = "service_0cuylcq";  // Thay bằng Service ID của bạn
  final String _templateId = "template_yth00xg"; // Thay bằng Template ID của bạn
  final String _publicKey = "5glYDek-o_3jvlxF2"; // Thay bằng Public Key của bạn

  final String _url = "https://api.emailjs.com/api/v1.0/email/send";

  Future<void> sendWarningEmail({
    required String userEmail,
    required String userName,
    required String medicineName,
    required double risk,
  }) async {
    try {
      final url = Uri.parse(_url);
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
          'template_params': {
            'to_email': userEmail,       // Email người nhận (quan trọng nhất)
            'to_name': userName,         // Tên hiển thị trong mail
            'medicine_name': medicineName,
            'risk_score': (risk * 100).toStringAsFixed(1), // Chuyển 0.85 -> 85.0
          }
        }),
      );

      if (response.statusCode == 200) {
        print("✅ Đã gửi email cảnh báo thành công tới: $userEmail");
      } else {
        print("❌ Gửi email thất bại: ${response.body}");
      }
    } catch (e) {
      print("❌ Lỗi kết nối Email Service: $e");
    }
  }
}