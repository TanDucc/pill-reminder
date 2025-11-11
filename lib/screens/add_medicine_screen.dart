import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';

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

      setState(() {
        _morningTime = (data['morning_hour'] != null && data['morning_minute'] != null)
            ? TimeOfDay(hour: data['morning_hour'], minute: data['morning_minute'])
            : null;
        _noonTime = (data['noon_hour'] != null && data['noon_minute'] != null)
            ? TimeOfDay(hour: data['noon_hour'], minute: data['noon_minute'])
            : null;

Future<void> _saveTimes() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final uid = user.uid;
  // ignore: avoid_print
  print('Attempting to save medicine times for uid: $uid');

  Map<String, dynamic> makePayload(DateTime day) => {
        'medicine': _medicineController.text.trim(),
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

  if (_applyToWeek) {
    // Prepare Firestore batch and RTDB multi-path
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
      });

      updates['/medicine_times/$uid/days/$dayId'] = payload;
    }

    // Try Firestore batch
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
  } else if (!firestoreOk && rtdbOk) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('⚠️ Firestore failed, but saved to Realtime DB.\nFirestore error: $firestoreErr')),
    );
  } else if (firestoreOk && !rtdbOk) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('⚠️ Saved to Firestore, but Realtime DB failed.\nRTDB error: $rtdbErr')),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Failed to save to both Firestore and Realtime DB.\nFirestore: $firestoreErr\nRTDB: $rtdbErr')),
    );
  }
}        _eveningTime = (data['evening_hour'] != null && data['evening_minute'] != null)
            ? TimeOfDay(hour: data['evening_hour'], minute: data['evening_minute'])
            : null;
      });
    } else {
      _medicineController.text = '';
      setState(() {
        _morningTime = null;
        _noonTime = null;
        _eveningTime = null;
      });
    }
  }

  /// 🔹 Hàm lưu giờ vào Firestore
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
          'morning_hour': _morningTime?.hour,
          'morning_minute': _morningTime?.minute,
          'noon_hour': _noonTime?.hour,
          'noon_minute': _noonTime?.minute,
          'evening_hour': _eveningTime?.hour,
          'evening_minute': _eveningTime?.minute,
          'date': day.toIso8601String().substring(0, 10),
          'createdAt': ServerValue.timestamp,
        };

    // If apply to week is enabled, write the same times for selected date + next 6 days
    try {
      if (_applyToWeek) {
        final batch = FirebaseFirestore.instance.batch();
        final Map<String, Object?> updates = {}; // for RTDB multi-path update
        for (int i = 0; i < 7; i++) {
          final day = _selectedDate.add(Duration(days: i));
          final docRef = FirebaseFirestore.instance
              .collection('medicine_times')
              .doc(uid)
              .collection('days')
              .doc(day.toIso8601String().substring(0, 10));

          final payload = makePayload(day);
          // Firestore batch
          batch.set(docRef, {
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
            'appliedWeek': true,
          });
          // RTDB multi-path (path: /medicine_times/{uid}/days/{date})
          updates['/medicine_times/$uid/days/${day.toIso8601String().substring(0, 10)}'] = payload;
        }

        await batch.commit();
        if (updates.isNotEmpty) {
          await _rtdb.update(updates);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Đã lưu giờ uống thuốc cho 1 tuần!')),
        );
      } else {
        final docRef = FirebaseFirestore.instance
            .collection('medicine_times')
            .doc(uid)
            .collection('days')
            .doc(_selectedDate.toIso8601String().substring(0, 10));

        final payload = makePayload(_selectedDate);
        await docRef.set({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
        // write to Realtime Database single path
        await _rtdb
            .child('medicine_times/$uid/days/${_selectedDate.toIso8601String().substring(0, 10)}')
            .set(payload);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Đã lưu giờ uống thuốc!')),
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
                child: Text(
                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
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
        ],
      ),
    );
  }

  /// 🔹 Widget chọn giờ (đã bỏ phần hiển thị giờ bên cạnh)
  Widget _buildTimeSection(
      String title, TimeOfDay? time, Function(TimeOfDay) onTimePicked) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time ?? TimeOfDay.now(),
                    );
                    if (picked != null) {
                      onTimePicked(picked);
                    }
                  },
                  child: Text(time != null
                      ? _formatTime(time)
                      : 'Chọn giờ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
