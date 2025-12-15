import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Để lấy email user hiện tại
import 'email_service.dart'; // [MỚI] Import file email service vừa tạo

class PredictionService {
  final String _apiUrl = "https://pillbox-model-api-907590581785.us-central1.run.app/predict";

  Future<double?> runDailyCheck(String userId) async {
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // --- Logic lấy ngày hôm qua ---
    DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    String yesterdayStr = DateFormat('yyyy-MM-dd').format(yesterday);

    try {
      // 1. Kiểm tra xem hôm nay đã có kết quả chưa?
      DocumentReference todayDocRef = FirebaseFirestore.instance
          .collection('medicine_times')
          .doc(userId)
          .collection('days')
          .doc(todayStr);

      DocumentSnapshot todayDoc = await todayDocRef.get();

      if (todayDoc.exists) {
        Map<String, dynamic> todayData = todayDoc.data() as Map<String, dynamic>;
        if (todayData.containsKey('prediction_risk')) {
          print("Đã có kết quả dự đoán hôm nay.");
          return (todayData['prediction_risk'] as num).toDouble();
        }
      }

      // 2. Lấy dữ liệu ngày hôm qua
      DocumentSnapshot yesterdayDoc = await FirebaseFirestore.instance
          .collection('medicine_times')
          .doc(userId)
          .collection('days')
          .doc(yesterdayStr)
          .get();

      if (!yesterdayDoc.exists) {
        print("Không có dữ liệu ngày hôm qua để dự đoán.");
        return null; 
      }

      Map<String, dynamic> data = yesterdayDoc.data() as Map<String, dynamic>;

      // 3. Xử lý Logic thời gian
      int pHour = data['morning_hour'] ?? 8; 
      int pMinute = data['morning_minute'] ?? 0;
      DateTime prescribedTime = DateTime(yesterday.year, yesterday.month, yesterday.day, pHour, pMinute);

      DateTime actualTime;
      if (data['esp32_morning_hour'] != null) {
        int aHour = data['esp32_morning_hour'];
        int aMinute = data['esp32_morning_minute'] ?? 0;
        actualTime = DateTime(yesterday.year, yesterday.month, yesterday.day, aHour, aMinute);
      } else {
        print("Không mở nắp sáng hôm qua. Cộng 15 phút.");
        actualTime = prescribedTime.add(const Duration(minutes: 30));
      }

      // 4. Gọi API AI Model
      Map<String, dynamic> payload = {
        "patient_id": [userId],
        "age": [data['user_age'] ?? 25], 
        "gender": [(data['user_gender'] == null || data['user_gender'] == "") ? "M" : data['user_gender']],
        "chronic_condition": [(data['disease'] == null || data['disease'] == "") ? "unknown" : data['disease']],
        "medication_name": [(data['medicine'] == null || data['medicine'] == "") ? "General" : data['medicine']],
        "dosage": [3],
        "Actual_Intake_Timestamp": [actualTime.toUtc().toIso8601String()],
        "Prescribed_Time": [prescribedTime.toUtc().toIso8601String()],
      };

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        // Xử lý kết quả trả về
        final dynamic decodedResponse = jsonDecode(response.body);
        double risk = 0.0;

        if (decodedResponse is List && decodedResponse.isNotEmpty) {
           risk = (decodedResponse[0]['predicted_non_adherence_risk'] ?? 0.0).toDouble();
        } else if (decodedResponse is Map) {
           var riskValue = decodedResponse['predicted_non_adherence_risk'];
           if (riskValue is Map) risk = (riskValue.values.first ?? 0.0).toDouble();
           else if (riskValue is List) risk = (riskValue.isNotEmpty ? riskValue[0] : 0.0).toDouble();
           else risk = (riskValue ?? 0.0).toDouble();
        }

        // --- PHẦN MỚI: GỬI MAIL NẾU RỦI RO CAO ---
        if (risk > 0.85) {
          print("⚠️ Rủi ro cao ($risk). Tiến hành gửi mail...");
          await _triggerEmailAlert(userId, data['medicine'] ?? "Thuốc", risk);
        }
        // ------------------------------------------

        // Lưu kết quả vào Firebase
        await todayDocRef.set({
          'prediction_risk': risk,            
          'prediction_source_date': yesterdayStr, 
          'last_prediction_time': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return risk;
      } else {
        print("Lỗi API: ${response.body}");
        return null;
      }

    } catch (e) {
      print("Lỗi PredictionService: $e");
      return null;
    }
  }

  // --- HÀM PHỤ TRỢ ĐỂ GỬI MAIL ---
  Future<void> _triggerEmailAlert(String userId, String medicineName, double risk) async {
    // 1. Lấy Email của user hiện tại
    final user = FirebaseAuth.instance.currentUser;
    String? email = user?.email;
    String name = user?.displayName ?? "Người dùng";

    // Nếu Auth không có email (ví dụ login ẩn danh), thử tìm trong Firestore
    if (email == null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (userDoc.exists) {
          email = userDoc.get('email');
          name = userDoc.get('name') ?? name;
        }
      } catch (e) {
        print("Không tìm thấy email trong Firestore.");
      }
    }

    // 2. Gọi EmailService nếu có địa chỉ email
    if (email != null && email.isNotEmpty) {
      EmailService emailService = EmailService();
      await emailService.sendWarningEmail(
        userEmail: email,
        userName: name,
        medicineName: medicineName,
        risk: risk,
      );
    } else {
      print("⚠️ Không tìm thấy địa chỉ email để gửi cảnh báo.");
    }
  }
}