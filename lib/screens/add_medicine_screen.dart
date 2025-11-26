import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/notification_service.dart';

class AddMedicineScreen extends StatefulWidget {
  const AddMedicineScreen({super.key});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  TimeOfDay? _morningTime;
  TimeOfDay? _noonTime;
  TimeOfDay? _eveningTime;
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _medicineController = TextEditingController();
  final TextEditingController _diseaseController = TextEditingController();
  bool _applyToWeek = false; // ...new: whether to apply times for 1 week
  final DatabaseReference _rtdb = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://smart-pillbox-54626-default-rtdb.asia-southeast1.firebasedatabase.app',
  ).ref();

  @override
  void initState() {
    super.initState();
    _loadTimesForDate(_selectedDate);
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
      });
    } else {
      _medicineController.text = '';
      _diseaseController.text = '';
      setState(() {
        _morningTime = null;
        _noonTime = null;
        _eveningTime = null;
      });
    }
  }

  /// 🔹 Hàm lưu giờ vào Firestore và Realtime Database
  Future<void> _saveTimes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Log UID for debugging and prepare the data payload (same structure for Firestore & RTDB)
    final uid = user.uid;
    // helpful debug - will appear in console
    // ignore: avoid_print
    print('Attempting to save medicine times for uid: $uid');

    // Prepare the data payload (same structure for Firestore & RTDB)
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
        };

    bool firestoreOk = true;
    String? firestoreErr;
    bool rtdbOk = true;
    String? rtdbErr;

    try {
      if (_applyToWeek) {
        final batch = FirebaseFirestore.instance.batch();
        final Map<String, Object?> updates = {}; // for RTDB multi-path update
        for (int i = 0; i < 7; i++) {
          final day = _selectedDate.add(Duration(days: i));
          final dayId = day.toIso8601String().substring(0, 10);
          final docRef = FirebaseFirestore.instance
              .collection('medicine_times')
              .doc(uid)
              .collection('days')
              .doc(dayId);

          final payload = makePayload(day);
          // Firestore batch
          batch.set(docRef, {
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
            'appliedWeek': true,
          });
          // RTDB multi-path (path: /medicine_times/{uid}/days/{date})
          updates['/medicine_times/$uid/days/$dayId'] = payload;
        }

        // Try Firestore commit
        try {
          await batch.commit();
        } on FirebaseException catch (e) {
          firestoreOk = false;
          firestoreErr = '${e.code} - ${e.message}';
          // ignore: avoid_print
          print('Firestore batch commit failed: $firestoreErr');
        } catch (e) {
          firestoreOk = false;
          firestoreErr = e.toString();
          // ignore: avoid_print
          print('Unexpected Firestore error: $firestoreErr');
        }

        // Try RTDB update regardless of Firestore result
        try {
          if (updates.isNotEmpty) {
            await _rtdb.update(updates);
          }
        } on FirebaseException catch (e) {
          rtdbOk = false;
          rtdbErr = '${e.code} - ${e.message}';
          // ignore: avoid_print
          print('RTDB update failed: $rtdbErr');
        } catch (e) {
          rtdbOk = false;
          rtdbErr = e.toString();
          // ignore: avoid_print
          print('Unexpected RTDB error: $rtdbErr');
        }

        // Đặt lịch thông báo cho từng ngày trong 7 ngày
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
              print('Loại thuốc: ${data['medicine'] ?? ''}');
              print('Sáng: ${data['morning_hour'] ?? '--'}:${data['morning_minute'] ?? '--'}');
              print('Trưa: ${data['noon_hour'] ?? '--'}:${data['noon_minute'] ?? '--'}');
              print('Tối: ${data['evening_hour'] ?? '--'}:${data['evening_minute'] ?? '--'}');
              await NotificationService().scheduleTodaysNotifications(uid: uid);
              print('✅ Đã xếp lịch thông báo cho ngày $dayId');
            } else {
              print('⏩ Bỏ qua ngày $dayId (trước hôm nay)');
            }
          } else {
            print('❌ Không tìm thấy dữ liệu cho ngày $dayId');
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

        // Firestore write
        try {
          await docRef.set({
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } on FirebaseException catch (e) {
          firestoreOk = false;
          firestoreErr = '${e.code} - ${e.message}';
          // ignore: avoid_print
          print('Firestore set failed: $firestoreErr');
        } catch (e) {
          firestoreOk = false;
          firestoreErr = e.toString();
          // ignore: avoid_print
          print('Unexpected Firestore error: $firestoreErr');
        }

        // RTDB write
        try {
          await _rtdb
              .child('medicine_times/$uid/days/$dayId')
              .set(payload);
        } on FirebaseException catch (e) {
          rtdbOk = false;
          rtdbErr = '${e.code} - ${e.message}';
          // ignore: avoid_print
          print('RTDB set failed: $rtdbErr');
        } catch (e) {
          rtdbOk = false;
          rtdbErr = e.toString();
          // ignore: avoid_print
          print('Unexpected RTDB error: $rtdbErr');
        }
      }

      // Summarize results to user
      if (firestoreOk && rtdbOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_applyToWeek ? '✅ Đã lưu giờ uống thuốc cho 1 tuần!' : '✅ Đã lưu giờ uống thuốc!')),
        );
        // Schedule notifications if today
        if (_selectedDate.toIso8601String().substring(0, 10) == DateTime.now().toIso8601String().substring(0, 10)) {
          print('📅 Selected date is today, scheduling notifications...');
          await NotificationService().scheduleTodaysNotifications();
        } else {
          print('🚫 Selected date is not today, skipping notification schedule');
        }
      } else if (!firestoreOk && rtdbOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Firestore failed, but saved to Realtime DB.\nFirestore error: $firestoreErr')),
        );
        // Schedule notifications if today
        if (_selectedDate.toIso8601String().substring(0, 10) == DateTime.now().toIso8601String().substring(0, 10)) {
          await NotificationService().scheduleTodaysNotifications();
        }
      } else if (firestoreOk && !rtdbOk) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Saved to Firestore, but Realtime DB failed.\nRTDB error: $rtdbErr')),
        );
        // Schedule notifications if today
        if (_selectedDate.toIso8601String().substring(0, 10) == DateTime.now().toIso8601String().substring(0, 10)) {
          await NotificationService().scheduleTodaysNotifications();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to save to both Firestore and Realtime DB.\nFirestore: $firestoreErr\nRTDB: $rtdbErr')),
        );
      }
    } on FirebaseException catch (e) {
      // Log and show helpful message
      // ignore: avoid_print
      print('FirebaseException while saving times: ${e.code} - ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi lưu: ${e.code} - ${e.message}\nKiểm tra Firestore rules và quyền truy cập.')),
      );
    } catch (e) {
      // ignore: avoid_print
      print('Unexpected error while saving times: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xảy ra lỗi không xác định khi lưu dữ liệu.')),
      );
    }
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

          // ...new: switch to apply times to 1 week
          SwitchListTile(
            title: const Text('Áp dụng cho 1 tuần'),
            subtitle: const Text('Lưu cùng một lịch cho 7 ngày liên tiếp, bắt đầu từ ngày đã chọn'),
            value: _applyToWeek,
            onChanged: (v) {
              setState(() => _applyToWeek = v);
            },
          ),

          /// Giờ uống buổi sáng
          _buildTimeSection('Buổi sáng', _morningTime, (time) {
            setState(() => _morningTime = time);
          }),
          const SizedBox(height: 16),

          /// Giờ uống buổi trưa
          _buildTimeSection('Buổi trưa', _noonTime, (time) {
            setState(() => _noonTime = time);
          }),
          const SizedBox(height: 16),

          /// Giờ uống buổi tối
          _buildTimeSection('Buổi tối', _eveningTime, (time) {
            setState(() => _eveningTime = time);
          }),
          const SizedBox(height: 24),

          /// Nút lưu
          ElevatedButton(
            onPressed: _saveTimes,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('💾 Lưu giờ uống thuốc'),
          ),
          const SizedBox(height: 16),
          /// Nút test thông báo ngay lập tức
          ElevatedButton(
            onPressed: () async {
              await NotificationService().showImmediateTestNotification(message: 'Đây là thông báo TEST tức thì!');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã gửi thông báo ngay lập tức!')),
              );
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('📢 Test thông báo NGAY'),
          ),
          const SizedBox(height: 8),
          /// Nút test thông báo
          ElevatedButton(
            onPressed: () async {
              await NotificationService().scheduleTestNotification(message: 'Đây là thông báo test để kiểm tra thông báo hoạt động!');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã lập lịch thông báo test trong 2 phút!')),
              );
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('🔔 Test thông báo trong 2 phút'),
          ),
        ],
      ),
    );
  }
}
