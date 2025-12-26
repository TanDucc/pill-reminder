import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../services/prediction_service.dart';

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  TimeOfDay? _morningTime;
  TimeOfDay? _noonTime;
  TimeOfDay? _eveningTime;
  TimeOfDay? _esp32MorningTime;
  TimeOfDay? _esp32NoonTime;
  TimeOfDay? _esp32EveningTime;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _medicineController = TextEditingController();
  final TextEditingController _diseaseController = TextEditingController();
  bool _applyToWeek = false; 
  final DatabaseReference _rtdb = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://smart-pillbox-54626-default-rtdb.asia-southeast1.firebasedatabase.app',
  ).ref();
  
  double? _riskScore;
  double? _optimalTimeDiff; // [MỚI] Biến lưu thời gian đề xuất
  bool _loadingRisk = false;

  @override
  void initState() {
    super.initState();
    _loadTimesForDate(_selectedDate);
    _fetchRiskScore();
  }

  /// 🔹 Hàm tải giờ từ Firestore
  Future<void> _loadTimesForDate(DateTime date) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('medicine_times')
        .doc(user.uid)
        .collection('days')
        .doc(date.toIso8601String().substring(0, 10));

    final doc = await docRef.get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      _medicineController.text = data['medicine'] ?? '';
      _diseaseController.text = data['disease'] ?? '';

      setState(() {
        _morningTime = (data['morning_hour'] != null && data['morning_minute'] != null)
            ? TimeOfDay(hour: data['morning_hour'], minute: data['morning_minute'])
            : null;
        _noonTime = (data['noon_hour'] != null && data['noon_minute'] != null)
            ? TimeOfDay(hour: data['noon_hour'], minute: data['noon_minute'])
            : null;
        _eveningTime = (data['evening_hour'] != null && data['evening_minute'] != null)
            ? TimeOfDay(hour: data['evening_hour'], minute: data['evening_minute'])
            : null;
        _esp32MorningTime = (data['esp32_morning_hour'] != null && data['esp32_morning_minute'] != null)
            ? TimeOfDay(hour: data['esp32_morning_hour'], minute: data['esp32_morning_minute'])
            : null;
        _esp32NoonTime = (data['esp32_noon_hour'] != null && data['esp32_noon_minute'] != null)
            ? TimeOfDay(hour: data['esp32_noon_hour'], minute: data['esp32_noon_minute'])
            : null;
        _esp32EveningTime = (data['esp32_evening_hour'] != null && data['esp32_evening_minute'] != null)
            ? TimeOfDay(hour: data['esp32_evening_hour'], minute: data['esp32_evening_minute'])
            : null;

        // [MỚI] Load thêm dữ liệu AI nếu đã lưu
        if (data.containsKey('prediction_risk')) {
          _riskScore = (data['prediction_risk'] as num).toDouble();
        } else {
          _riskScore = null;
        }
        if (data.containsKey('optimal_time_diff')) {
          _optimalTimeDiff = (data['optimal_time_diff'] as num).toDouble();
        } else {
          _optimalTimeDiff = null;
        }
      });
    } else {
      _medicineController.text = '';
      _diseaseController.text = '';
      setState(() {
        _morningTime = null;
        _noonTime = null;
        _eveningTime = null;
        _esp32MorningTime = null;
        _esp32NoonTime = null;
        _esp32EveningTime = null;
        _riskScore = null;
        _optimalTimeDiff = null;
      });
    }
  }

  /// 🔹 Hàm lưu giờ vào Firestore và Realtime Database
  Future<void> _saveTimes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    print('Attempting to save medicine times for uid: $uid');

    // Fetch user data from Firestore
    Map<String, dynamic> userData = {};
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data()!;
        final name = data['name'] as String? ?? '';
        final gender = data['gender'] as String? ?? '';
        int? age;
        final dobTs = data['dob'];
        if (dobTs is Timestamp) {
          final dob = dobTs.toDate();
          age = DateTime.now().year - dob.year;
        }
        userData = {
          'user_name': name,
          'user_id': uid,
          'user_gender': gender,
          'user_age': age,
        };
      } else {
        userData = {
          'user_name': user.displayName ?? '',
          'user_id': uid,
          'user_gender': '',
          'user_age': null,
        };
      }
    } catch (e) {
      print('Error fetching user data: $e');
      userData = {
        'user_name': user.displayName ?? '',
        'user_id': uid,
        'user_gender': '',
        'user_age': null,
      };
    }

    // Prepare the data payload
    Map<String, dynamic> makePayload(DateTime day) => {
          'medicine': _medicineController.text.trim(),
          'disease': _diseaseController.text.trim(),
          'morning_hour': _morningTime?.hour,
          'morning_minute': _morningTime?.minute,
          'noon_hour': _noonTime?.hour,
          'noon_minute': _noonTime?.minute,
          'evening_hour': _eveningTime?.hour,
          'evening_minute': _eveningTime?.minute,
          'date': day.toIso8601String().substring(0, 10),
          'createdAt': ServerValue.timestamp,
          ...userData,
          // [MỚI] Giữ lại dữ liệu AI khi lưu để không bị mất
          if (_riskScore != null) 'prediction_risk': _riskScore,
          if (_optimalTimeDiff != null) 'optimal_time_diff': _optimalTimeDiff,
        };

    bool firestoreOk = true;
    String? firestoreErr;
    bool rtdbOk = true;
    String? rtdbErr;

    try {
      if (_applyToWeek) {
        final batch = FirebaseFirestore.instance.batch();
        final Map<String, Object?> updates = {}; 
        for (int i = 0; i < 7; i++) {
          final day = _selectedDate.add(Duration(days: i));
          final dayId = day.toIso8601String().substring(0, 10);
          final docRef = FirebaseFirestore.instance
              .collection('medicine_times')
              .doc(uid)
              .collection('days')
              .doc(dayId);

          final payload = makePayload(day);
          
          batch.set(docRef, {
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
            'appliedWeek': true,
          }, SetOptions(merge: true));
          
          updates['/medicine_times/$uid/days/$dayId'] = payload;
        }

        try {
          await batch.commit();
        } on FirebaseException catch (e) {
          firestoreOk = false;
          firestoreErr = '${e.code} - ${e.message}';
          print('Firestore batch commit failed: $firestoreErr');
        } catch (e) {
          firestoreOk = false;
          firestoreErr = e.toString();
          print('Unexpected Firestore error: $firestoreErr');
        }

        try {
          if (updates.isNotEmpty) {
            await _rtdb.update(updates);
          }
        } on FirebaseException catch (e) {
          rtdbOk = false;
          rtdbErr = '${e.code} - ${e.message}';
          print('RTDB update failed: $rtdbErr');
        } catch (e) {
          rtdbOk = false;
          rtdbErr = e.toString();
          print('Unexpected RTDB error: $rtdbErr');
        }

        // Đặt lịch thông báo
        for (int i = 0; i < 7; i++) {
          final day = _selectedDate.add(Duration(days: i));
          final dayId = day.toIso8601String().substring(0, 10);
          final docRef = FirebaseFirestore.instance
              .collection('medicine_times')
              .doc(uid)
              .collection('days')
              .doc(dayId);
          final doc = await docRef.get();
          if (doc.exists) {
            final data = doc.data() ?? {};
            final nowDateId = DateTime.now().toIso8601String().substring(0, 10);
            if (dayId.compareTo(nowDateId) >= 0) {
              print('--- Đặt lịch thông báo cho ngày $dayId ---');
              await NotificationService().scheduleTodaysNotifications(uid: uid);
              print('✅ Đã xếp lịch thông báo cho ngày $dayId');
            }
          }
        }
      } else {
        final dayId = _selectedDate.toIso8601String().substring(0, 10);
        final docRef = FirebaseFirestore.instance
            .collection('medicine_times')
            .doc(uid)
            .collection('days')
            .doc(dayId);

        final payload = makePayload(_selectedDate);

        try {
          await docRef.set({
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } on FirebaseException catch (e) {
          firestoreOk = false;
          firestoreErr = '${e.code} - ${e.message}';
          print('Firestore set failed: $firestoreErr');
        } catch (e) {
          firestoreOk = false;
          firestoreErr = e.toString();
          print('Unexpected Firestore error: $firestoreErr');
        }

        try {
          await _rtdb
              .child('medicine_times/$uid/days/$dayId')
              .set(payload);
        } on FirebaseException catch (e) {
          rtdbOk = false;
          rtdbErr = '${e.code} - ${e.message}';
          print('RTDB set failed: $rtdbErr');
        } catch (e) {
          rtdbOk = false;
          rtdbErr = e.toString();
          print('Unexpected RTDB error: $rtdbErr');
        }
      }

      if (firestoreOk && rtdbOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_applyToWeek ? '✅ Đã lưu giờ uống thuốc cho 1 tuần!' : '✅ Đã lưu giờ uống thuốc!')),
        );
        if (_selectedDate.toIso8601String().substring(0, 10) == DateTime.now().toIso8601String().substring(0, 10)) {
          print('📅 Selected date is today, scheduling notifications...');
          await NotificationService().scheduleTodaysNotifications();
        }
      } else if (!firestoreOk && rtdbOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Firestore failed, but saved to Realtime DB.\nFirestore error: $firestoreErr')),
        );
        if (_selectedDate.toIso8601String().substring(0, 10) == DateTime.now().toIso8601String().substring(0, 10)) {
          await NotificationService().scheduleTodaysNotifications();
        }
      } else if (firestoreOk && !rtdbOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Saved to Firestore, but Realtime DB failed.\nRTDB error: $rtdbErr')),
        );
        if (_selectedDate.toIso8601String().substring(0, 10) == DateTime.now().toIso8601String().substring(0, 10)) {
          await NotificationService().scheduleTodaysNotifications();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to save to both Firestore and Realtime DB.\nFirestore: $firestoreErr\nRTDB: $rtdbErr')),
        );
      }
    } on FirebaseException catch (e) {
      print('FirebaseException while saving times: ${e.code} - ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi lưu: ${e.code} - ${e.message}\nKiểm tra Firestore rules và quyền truy cập.')),
      );
    } catch (e) {
      print('Unexpected error while saving times: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xảy ra lỗi không xác định khi lưu dữ liệu.')),
      );
    }
  }

  Future<void> _fetchRiskScore() async {
    setState(() { _loadingRisk = true; });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() { _riskScore = null; _optimalTimeDiff = null; _loadingRisk = false; });
      return;
    }
    
    // Gọi API (Service đã tự lưu kết quả vào Firestore)
    final risk = await PredictionService().runDailyCheck(user.uid);
    
    // [MỚI] Đọc lại optimal_time_diff từ Firestore để hiển thị
    double? optimalDiff;
    try {
      String dateStr = _selectedDate.toIso8601String().substring(0, 10);
      final doc = await FirebaseFirestore.instance
            .collection('medicine_times')
            .doc(user.uid)
            .collection('days')
            .doc(dateStr)
            .get();
      if (doc.exists) {
         final data = doc.data() as Map<String, dynamic>;
         if (data.containsKey('optimal_time_diff')) {
            optimalDiff = (data['optimal_time_diff'] as num).toDouble();
         }
      }
    } catch (e) {
      print("Lỗi đọc optimal time: $e");
    }

    setState(() {
      _riskScore = risk;
      _optimalTimeDiff = optimalDiff;
      _loadingRisk = false;
    });
  }

  /// 🔹 Định dạng giờ
  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildTimeSection(String label, TimeOfDay? time, ValueChanged<TimeOfDay> onSet) {
    return Row(
      children: [
        Expanded(
          child: Text(label),
        ),
        Text(time != null ? _formatTime(time) : '--:--'),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time ?? TimeOfDay(hour: 8, minute: 0),
            );
            if (picked != null) onSet(picked);
          },
          child: const Text('Chọn'),
        ),
      ],
    );
  }

  // [MỚI] Widget hiển thị đề xuất thời gian
  Widget _buildOptimizationInfo() {
    if (_optimalTimeDiff == null) return const SizedBox.shrink();

    String message = "";
    IconData icon = Icons.check_circle;
    Color color = Colors.green[800]!;
    
    double val = double.parse(_optimalTimeDiff!.toStringAsFixed(1));

    if (val < -5) {
      message = "Đề xuất: Uống SỚM HƠN ${val.abs()} phút";
      icon = Icons.history; 
      color = Colors.orange[900]!;
    } else if (val > 5) {
      message = "Đề xuất: Uống MUỘN HƠN $val phút";
      icon = Icons.update;
      color = Colors.blue[900]!;
    } else {
      message = "Thời gian uống thuốc hiện tại khá tốt.";
      icon = Icons.thumb_up;
      color = Colors.green[900]!;
    }

    return Column(
      children: [
        const Divider(color: Colors.black26, height: 20, thickness: 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thêm giờ uống thuốc',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),

          /// Nhập loại thuốc
          TextField(
            controller: _medicineController,
            decoration: const InputDecoration(
              labelText: 'Loại thuốc dùng trong ngày',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          /// Nhập loại bệnh
          TextField(
            controller: _diseaseController,
            decoration: const InputDecoration(
              labelText: 'Loại bệnh (nếu có)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          /// Chọn ngày
          Row(
            children: [
              const Text('Chọn ngày: '),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2023),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                    });
                    await _loadTimesForDate(picked);
                  }
                },
                child: Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
              ),
            ],
          ),

          // Switch áp dụng cho 1 tuần
          SwitchListTile(
            title: const Text('Áp dụng cho 1 tuần'),
            subtitle: const Text('Lưu cùng một lịch cho 7 ngày liên tiếp, bắt đầu từ ngày đã chọn'),
            value: _applyToWeek,
            onChanged: (v) {
              setState(() => _applyToWeek = v);
            },
          ),

          /// Giờ uống buổi sáng
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimeSection('Buổi sáng', _morningTime, (time) {
                    setState(() => _morningTime = time);
                  }),
                  if (_esp32MorningTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Đã mở hộp thuốc vào lúc ${_formatTime(_esp32MorningTime!)}',
                        style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),

          /// Giờ uống buổi trưa
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimeSection('Buổi trưa', _noonTime, (time) {
                    setState(() => _noonTime = time);
                  }),
                  if (_esp32NoonTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Đã mở hộp thuốc vào lúc ${_formatTime(_esp32NoonTime!)}',
                        style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),

          /// Giờ uống buổi tối
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimeSection('Buổi tối', _eveningTime, (time) {
                    setState(() => _eveningTime = time);
                  }),
                  if (_esp32EveningTime != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Đã mở hộp thuốc vào lúc ${_formatTime(_esp32EveningTime!)}',
                        style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Hiển thị kết quả dự đoán tỉ lệ bỏ thuốc & Đề xuất tối ưu
          if (_loadingRisk)
            const Center(child: CircularProgressIndicator()),
          if (!_loadingRisk && _riskScore != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _riskScore! > 0.8
                    ? Colors.red[100]
                    : _riskScore! > 0.5
                        ? Colors.yellow[100]
                        : Colors.green[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _riskScore! > 0.8
                      ? Colors.red
                      : _riskScore! > 0.5
                          ? Colors.yellow[700]!
                          : Colors.green,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Dự đoán tỉ lệ bỏ/quên thuốc',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 60,
                    width: 60,
                    child: CircularProgressIndicator(
                      value: _riskScore!.clamp(0, 1),
                      strokeWidth: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _riskScore! > 0.8
                            ? Colors.red
                            : _riskScore! > 0.5
                                ? Colors.yellow[700]!
                                : Colors.green,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_riskScore! * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _riskScore! > 0.8
                          ? Colors.red
                          : _riskScore! > 0.5
                              ? Colors.yellow[700]!
                              : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_riskScore! > 0.8)
                    const Text('🔴 Nguy cơ rất cao, hãy chú ý nhắc nhở người bệnh tuân thủ uống thuốc!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  if (_riskScore! > 0.5 && _riskScore! <= 0.8)
                    const Text('🟡 Nguy cơ trung bình, người bệnh cần chú ý hơn!', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  if (_riskScore! <= 0.5)
                    const Text('🟢 Nguy cơ thấp, người bệnh đang tuân thủ tốt!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  
                  // [MỚI] Hiển thị đề xuất thời gian ngay bên dưới
                  _buildOptimizationInfo(),
                ],
              ),
            ),
          const SizedBox(height: 24),

          /// Nút lưu
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 16),
            child: ElevatedButton(
              onPressed: _saveTimes,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.save, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Lưu giờ uống thuốc',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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