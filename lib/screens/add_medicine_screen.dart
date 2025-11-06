import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
        _eveningTime = (data['evening_hour'] != null && data['evening_minute'] != null)
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

    final docRef = FirebaseFirestore.instance
        .collection('medicine_times')
        .doc(user.uid)
        .collection('days')
        .doc(_selectedDate.toIso8601String().substring(0, 10));

    await docRef.set({
      'medicine': _medicineController.text.trim(),
      'morning_hour': _morningTime?.hour,
      'morning_minute': _morningTime?.minute,
      'noon_hour': _noonTime?.hour,
      'noon_minute': _noonTime?.minute,
      'evening_hour': _eveningTime?.hour,
      'evening_minute': _eveningTime?.minute,
      'date': _selectedDate.toIso8601String().substring(0, 10),
      'createdAt': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Đã lưu giờ uống thuốc!')),
    );
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
