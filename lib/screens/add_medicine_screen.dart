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

  Future<void> _saveTimes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final docRef = FirebaseFirestore.instance
        .collection('medicine_times')
        .doc(user.uid)
        .collection('days')
        .doc(_selectedDate.toIso8601String().substring(0, 10));
    await docRef.set({
      'morning': _morningTime != null ? _morningTime!.format(context) : null,
      'noon': _noonTime != null ? _noonTime!.format(context) : null,
      'evening': _eveningTime != null ? _eveningTime!.format(context) : null,
      'date': _selectedDate.toIso8601String().substring(0, 10),
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu giờ uống thuốc!')),
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
                  }
                },
                child: Text(
                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
              ),
            ],
          ),
          _buildTimeSection('Buổi sáng', _morningTime, (time) {
            setState(() {
              _morningTime = time;
            });
          }),
          const SizedBox(height: 16),
          _buildTimeSection('Buổi trưa', _noonTime, (time) {
            setState(() {
              _noonTime = time;
            });
          }),
          const SizedBox(height: 16),
          _buildTimeSection('Buổi tối', _eveningTime, (time) {
            setState(() {
              _eveningTime = time;
            });
          }),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saveTimes,
            child: const Text('Lưu giờ uống thuốc'),
          ),
        ],
      ),
    );
  }

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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
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
                  child: Text(
                      time != null ? time.format(context) : 'Chọn giờ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}