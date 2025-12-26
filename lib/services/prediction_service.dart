import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'email_service.dart'; 

class PredictionService {
  // URL API cũ (Dự đoán rủi ro)
  final String _riskApiUrl = "https://pillbox-model-api-907590581785.us-central1.run.app/predict";
  
  // [MỚI] URL API mới (Đề xuất thời gian tối ưu)
  final String _optimalLagUrl = "https://pillbox-model-api-907590581785.us-central1.run.app/predict_optimal_lag";

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
        // Nếu đã có đủ cả risk và time_diff thì trả về risk luôn
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
        print("Không mở nắp sáng hôm qua. Cộng 30 phút.");
        actualTime = prescribedTime.add(const Duration(minutes: 60));
      }

      // 4. Chuẩn bị Payload
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

      // 5. GỌI API (Song song)
      final responseRisk = await http.post(
        Uri.parse(_riskApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      final responseLag = await http.post(
        Uri.parse(_optimalLagUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      double risk = 0.0;
      double optimalTimeDiff = 0.0; 

      // Xử lý kết quả API Rủi ro
      if (responseRisk.statusCode == 200) {
        final dynamic decoded = jsonDecode(responseRisk.body);
        if (decoded is List && decoded.isNotEmpty) {
           risk = (decoded[0]['predicted_non_adherence_risk'] ?? 0.0).toDouble();
        } else if (decoded is Map) {
           var val = decoded['predicted_non_adherence_risk'];
           risk = (val is List && val.isNotEmpty) ? (val[0] as num).toDouble() : (val as num? ?? 0.0).toDouble();
        }
      }

      // [SỬA LỖI] Xử lý kết quả API Thời gian tối ưu
      if (responseLag.statusCode == 200) {
        try {
          final dynamic decodedLag = jsonDecode(responseLag.body);
          
          // --- ĐOẠN ĐƯỢC SỬA LẠI (Bỏ comment dòng if) ---
          if (decodedLag is List && decodedLag.isNotEmpty) {
             // API trả về mảng, lấy phần tử đầu tiên
             optimalTimeDiff = (decodedLag[0]['predicted_time_difference_minutes'] ?? 0.0).toDouble();
          } else if (decodedLag is Map) {
             var val = decodedLag['predicted_time_difference_minutes'];
             if (val is List && val.isNotEmpty) {
                 optimalTimeDiff = (val[0] as num).toDouble();
             } else {
                 optimalTimeDiff = (val as num? ?? 0.0).toDouble();
             }
          }
          // ----------------------------------------------
          
          print("✅ Đề xuất điều chỉnh thời gian: $optimalTimeDiff phút");
        } catch (e) {
          print("Lỗi parse API Optimal Lag: $e");
        }
      }

      // --- GỬI MAIL NẾU RỦI RO CAO ---
      if (risk > 0.85) {
        print("⚠️ Rủi ro cao ($risk). Tiến hành gửi mail...");
        await _triggerEmailAlert(userId, data['medicine'] ?? "Thuốc", risk);
      }

      // --- LƯU KẾT QUẢ VÀO FIREBASE ---
      await todayDocRef.set({
        'prediction_risk': risk,            
        'optimal_time_diff': optimalTimeDiff, 
        'prediction_source_date': yesterdayStr, 
        'last_prediction_time': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return risk;

    } catch (e) {
      print("Lỗi PredictionService: $e");
      return null;
    }
  }

  // --- HÀM PHỤ TRỢ ĐỂ GỬI MAIL ---
  Future<void> _triggerEmailAlert(String userId, String medicineName, double risk) async {
    print("--- BẮT ĐẦU QUY TRÌNH GỬI MAIL ---");
    final user = FirebaseAuth.instance.currentUser;
    String? email = user?.email;
    String name = user?.displayName ?? "Người dùng";

    if (email == null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (userDoc.exists) {
          Map<String, dynamic>? data = userDoc.data() as Map<String, dynamic>?;
          email = data?['email'];
          name = data?['name'] ?? name;
        }
      } catch (e) {
        print("Lỗi tìm trong Firestore: $e");
      }
    }

    if (email != null && email.isNotEmpty) {
      EmailService emailService = EmailService();
      await emailService.sendWarningEmail(
        userEmail: email,
        userName: name,
        medicineName: medicineName,
        risk: risk,
      );
    } else {
      print("❌ LỖI: Không có địa chỉ email nào để gửi!");
    }
    print("--- KẾT THÚC QUY TRÌNH ---");
  }
}