import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PredictionService {
  // Đường dẫn API
  final String _apiUrl = "https://pillbox-model-api-907590581785.us-central1.run.app/predict";

  // Hàm chính: Gọi mỗi khi vào màn hình Add Medicine
  Future<double?> runDailyCheck(String userId) async {
    // 1. Xác định ngày hôm nay và ngày hôm qua
    String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    String yesterdayStr = DateFormat('yyyy-MM-dd').format(yesterday);

    try {
      // 2. KIỂM TRA TRÊN FIREBASE: Xem hôm nay đã dự đoán chưa?
      DocumentReference todayDocRef = FirebaseFirestore.instance
          .collection('medicine_times')
          .doc(userId)
          .collection('days')
          .doc(todayStr);

      DocumentSnapshot todayDoc = await todayDocRef.get();

      // Nếu document hôm nay đã có và đã có trường 'prediction_risk' -> Trả về luôn
      if (todayDoc.exists) {
        Map<String, dynamic> todayData = todayDoc.data() as Map<String, dynamic>;
        if (todayData.containsKey('prediction_risk')) {
          print("Đã có kết quả dự đoán trên Firebase cho hôm nay ($todayStr).");
          return (todayData['prediction_risk'] as num).toDouble();
        }
      }

      // 3. Nếu chưa có -> Lấy dữ liệu NGÀY HÔM QUA
      DocumentSnapshot yesterdayDoc = await FirebaseFirestore.instance
          .collection('medicine_times')
          .doc(userId)
          .collection('days')
          .doc(yesterdayStr)
          .get();

      if (!yesterdayDoc.exists) {
        print("Không tìm thấy dữ liệu ngày hôm qua ($yesterdayStr) để dự đoán.");
        return null; 
      }

      Map<String, dynamic> data = yesterdayDoc.data() as Map<String, dynamic>;

      // 4. Xử lý Logic thời gian
      int pHour = data['morning_hour'] ?? 8; 
      int pMinute = data['morning_minute'] ?? 0;
      DateTime prescribedTime = DateTime(yesterday.year, yesterday.month, yesterday.day, pHour, pMinute);

      DateTime actualTime;
      if (data['esp32_morning_hour'] != null) {
        int aHour = data['esp32_morning_hour'];
        int aMinute = data['esp32_morning_minute'] ?? 0;
        actualTime = DateTime(yesterday.year, yesterday.month, yesterday.day, aHour, aMinute);
      } else {
        print("Không mở nắp sáng hôm qua. Tự động cộng 10 phút.");
        actualTime = prescribedTime.add(const Duration(minutes: 10));
      }

      // 5. Gọi API (Giữ nguyên các dấu [] để tránh lỗi scalar)
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

      print("Payload gửi đi: $payload");

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      print("API Response Body: ${response.body}"); // In ra để debug xem cấu trúc trả về là gì

      if (response.statusCode == 200) {
        // --- SỬA LỖI Ở ĐÂY ---
        // Chúng ta dùng dynamic vì chưa biết server trả về List hay Map
        final dynamic decodedResponse = jsonDecode(response.body);
        double risk = 0.0;

        // Trường hợp 1: Server trả về một List (Mảng) -> [ {"predicted_non_adherence_risk": 0.8} ]
        if (decodedResponse is List) {
          if (decodedResponse.isNotEmpty) {
            // Lấy phần tử đầu tiên [0] rồi mới truy cập key
            risk = (decodedResponse[0]['predicted_non_adherence_risk'] ?? 0.0).toDouble();
          }
        } 
        // Trường hợp 2: Server trả về một Map (Object) -> { "predicted_non_adherence_risk": ... }
        else if (decodedResponse is Map) {
          var riskValue = decodedResponse['predicted_non_adherence_risk'];
          
          // Đôi khi Pandas trả về dạng {"0": 0.8} hoặc [0.8] bên trong key đó
          if (riskValue is Map) {
             // Lấy giá trị đầu tiên trong map con
             risk = (riskValue.values.first ?? 0.0).toDouble();
          } else if (riskValue is List) {
             // Lấy giá trị đầu tiên trong list con
             risk = (riskValue.isNotEmpty ? riskValue[0] : 0.0).toDouble();
          } else {
             // Giá trị đơn bình thường
             risk = (riskValue ?? 0.0).toDouble();
          }
        }
        // ---------------------

        // 6. LƯU KẾT QUẢ VÀO FIREBASE
        await todayDocRef.set({
          'prediction_risk': risk,            
          'prediction_source_date': yesterdayStr, 
          'last_prediction_time': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print("Đã lưu kết quả dự đoán: $risk");
        return risk;
      } else {
        print("Lỗi API (${response.statusCode}): ${response.body}");
        return null;
      }

    } catch (e) {
      print("Lỗi PredictionService: $e");
      return null;
    }
  }
}