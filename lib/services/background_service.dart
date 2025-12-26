import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'prediction_service.dart'; // Import service dự đoán của bạn

// Định nghĩa tên task
const String taskSendEmail = "task_send_warning_email";
const String taskDailyCheck = "task_daily_prediction_check"; // [MỚI] Tên task định kỳ

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("⏰ Workmanager chạy task: $task");

    // Khởi tạo Firebase vì chạy ngầm
    await Firebase.initializeApp();

    if (task == taskSendEmail) {
       // ... (Code gửi mail hẹn giờ cũ của bạn giữ nguyên ở đây) ...
       return Future.value(true);
    }

    // --- [MỚI] XỬ LÝ TASK ĐỊNH KỲ HẰNG NGÀY ---
    if (task == taskDailyCheck) {
      try {
        // 1. Lấy User hiện tại (Lưu ý: User phải từng đăng nhập rồi mới có data)
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          print("❌ Không tìm thấy user đăng nhập trong background.");
          return Future.value(false);
        }

        // 2. Kiểm tra xem hôm nay đã làm chưa?
        String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        
        DocumentSnapshot todayDoc = await FirebaseFirestore.instance
            .collection('medicine_times')
            .doc(user.uid)
            .collection('days')
            .doc(todayStr)
            .get();

        // Nếu đã có kết quả dự đoán rồi thì thôi, không làm nữa
        if (todayDoc.exists) {
           Map<String, dynamic> data = todayDoc.data() as Map<String, dynamic>;
           if (data.containsKey('prediction_risk')) {
             print("✅ Hôm nay ($todayStr) đã dự đoán rồi. Bỏ qua.");
             return Future.value(true);
           }
        }

        // 3. Nếu chưa làm -> Gọi PredictionService chạy ngay lập tức
        print("🚀 Phát hiện ngày mới chưa dự đoán. Đang chạy AI...");
        PredictionService service = PredictionService();
        
        // Gọi hàm chạy dự đoán (Hàm này đã có sẵn logic gửi mail nếu risk > 0.85)
        double? result = await service.runDailyCheck(user.uid);
        
        if (result != null) {
          print("✅ Đã chạy ngầm thành công. Risk: $result");
        } else {
          print("⚠️ Chạy ngầm thất bại hoặc không có dữ liệu hôm qua.");
        }

      } catch (e) {
        print("❌ Lỗi task định kỳ: $e");
        return Future.value(false);
      }
    }

    return Future.value(true);
  });
}