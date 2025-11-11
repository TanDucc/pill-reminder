// dart
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, dynamic>? _dayData;
  bool _loadingDay = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadTimesForDate(_focusedDay);
  }

  Future<void> _loadTimesForDate(DateTime date) async {
    setState(() {
      _loadingDay = true;
      _dayData = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadingDay = false);
      return;
    }

    final dayId = date.toIso8601String().substring(0, 10);
    final docRef = FirebaseFirestore.instance
        .collection('medicine_times')
        .doc(user.uid)
        .collection('days')
        .doc(dayId);

    try {
      final doc = await docRef.get();
      setState(() {
        _dayData = doc.exists ? (doc.data() ?? {}) : null;
      });
    } catch (e) {
      // ignore: avoid_print
      print('Error loading day data: $e');
      setState(() {
        _dayData = null;
      });
    } finally {
      setState(() => _loadingDay = false);
    }
  }

  String _formatTimeFromFields(int? hour, int? minute) {
    if (hour == null || minute == null) return '';
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildTimesView() {
    if (_loadingDay) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dayData == null || (_dayData?['medicine'] == null && _dayData?['morning_hour'] == null)) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Chưa có lịch thuốc cho ngày đã chọn.'),
      );
    }

    final medicine = _dayData?['medicine'] as String? ?? '';
    final morning = _formatTimeFromFields(_dayData?['morning_hour'] as int?, _dayData?['morning_minute'] as int?);
    final noon = _formatTimeFromFields(_dayData?['noon_hour'] as int?, _dayData?['noon_minute'] as int?);
    final evening = _formatTimeFromFields(_dayData?['evening_hour'] as int?, _dayData?['evening_minute'] as int?);

    final items = <Widget>[];
    if (medicine.isNotEmpty) {
      items.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.medication),
          title: Text(medicine),
          subtitle: const Text('Loại thuốc'),
        ),
      ));
    }
    if (morning.isNotEmpty) {
      items.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.wb_sunny),
          title: const Text('Buổi sáng'),
          subtitle: Text('Thời gian: $morning'),
        ),
      ));
    }
    if (noon.isNotEmpty) {
      items.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: const Text('Buổi trưa'),
          subtitle: Text('Thời gian: $noon'),
        ),
      ));
    }
    if (evening.isNotEmpty) {
      items.add(Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
          leading: const Icon(Icons.nightlight_round),
          title: const Text('Buổi tối'),
          subtitle: Text('Thời gian: $evening'),
        ),
      ));
    }

    return items.isNotEmpty
        ? Column(children: items)
        : const Padding(
      padding: EdgeInsets.all(16.0),
      child: Text('Chưa có lịch thuốc cho ngày đã chọn.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TableCalendar(
          firstDay: DateTime.utc(2023, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          calendarFormat: _calendarFormat,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            if (!isSameDay(_selectedDay, selectedDay)) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              _loadTimesForDate(selectedDay);
            }
          },
          onFormatChanged: (format) {
            if (_calendarFormat != format) {
              setState(() {
                _calendarFormat = format;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: _buildTimesView(),
          ),
        ),
      ],
    );
  }
}
