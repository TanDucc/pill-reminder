import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz_core;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        // Handle notification tap
        print('Notification tapped: ${response.payload}');
      },
    );

    // Create notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'pill_reminder_channel',
      'Pill Reminder',
      description: 'Channel for pill reminders',
      importance: Importance.max,
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Request permissions explicitly
    flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();

    // WorkManager code removed - using zonedSchedule instead for background scheduling
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    // Debug print
    print('🎯 Scheduling notification ID $id for $scheduledDate');

    // Use DateTime directly (flutter_local_notifications will handle timezone)
    final DateTime notificationTime = scheduledDate;
    print('⏰ Notification time: $notificationTime');

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'pill_reminder_channel',
      'Pill Reminder',
      channelDescription: 'Channel for pill reminders',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableLights: true,
      enableVibration: true,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    try {
      // Make sure time is in future
      if (notificationTime.isBefore(DateTime.now())) {
        // print('⚠️ Scheduled time is in past, skipping notification');
        return;
      }

      // Create TZDateTime properly for zonedSchedule
      final scheduledTZTime = tz_core.TZDateTime.from(notificationTime, tz_core.local);
      // print('🕒 TZ Scheduled time: $scheduledTZTime');

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZTime,
        platformChannelSpecifics,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      print('✅ Notification scheduled successfully for ID $id');
    } catch (e) {
      print('❌ Error scheduling notification: $e');
      print('Full error: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  Future<void> scheduleTodaysNotifications({String? uid}) async {
    print('🔄 Starting to schedule todays notifications...');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null && uid == null) {
      print('❌ No user found for notifications');
      return;
    }

    final userId = uid ?? user!.uid;
    final today = DateTime.now();
    final dateId = today.toIso8601String().substring(0, 10);
    print('👤 User ID: $userId, Date: $dateId');

    try {
      final docRef = FirebaseFirestore.instance
          .collection('medicine_times')
          .doc(userId)
          .collection('days')
          .doc(dateId);

      final doc = await docRef.get();
      if (doc.exists) {
        final data = doc.data()!;
        final medicine = data['medicine'] as String? ?? '';
        // print('📄 Medicine data found: $medicine');
        // print('📊 Data: $data');

        // Cancel previous notifications first
        await cancelAllNotifications();
        // print('🚮 Cancelled all previous notifications');

        // Schedule morning notification
        if (data['morning_hour'] != null && data['morning_minute'] != null) {
          final morningTime = DateTime(
            today.year,
            today.month,
            today.day,
            data['morning_hour'] as int,
            data['morning_minute'] as int,
          );
          if (morningTime.isAfter(DateTime.now())) {
            await scheduleNotification(
              id: 1,
              title: 'Đến giờ uống thuốc',
              body: 'Đến giờ uống thuốc buổi sáng',
              scheduledDate: morningTime,
            );
          }
        }

        // Schedule noon notification
        if (data['noon_hour'] != null && data['noon_minute'] != null) {
          final noonTime = DateTime(
            today.year,
            today.month,
            today.day,
            data['noon_hour'] as int,
            data['noon_minute'] as int,
          );
          if (noonTime.isAfter(DateTime.now())) {
            await scheduleNotification(
              id: 2,
              title: 'Đến giờ uống thuốc',
              body: 'Đến giờ uống thuốc buổi trưa',
              scheduledDate: noonTime,
            );
          }
        }

        // Schedule evening notification
        if (data['evening_hour'] != null && data['evening_minute'] != null) {
          final eveningTime = DateTime(
            today.year,
            today.month,
            today.day,
            data['evening_hour'] as int,
            data['evening_minute'] as int,
          );
          if (eveningTime.isAfter(DateTime.now())) {
            await scheduleNotification(
              id: 3,
              title: 'Đến giờ uống thuốc',
              body: 'Đến giờ uống thuốc buổi tối',
              scheduledDate: eveningTime,
            );
          }
        }
      } else {
        print('❓ No medicine data found for today');
      }
    } catch (e) {
      print('❌ Error scheduling notifications: $e');
    }
  }

  Future<void> cancelTodaysNotifications() async {
    await cancelAllNotifications();
  }

  // Method for immediate test notification
  Future<void> scheduleTestNotification({String? message}) async {
    final testTime = DateTime.now().add(const Duration(minutes: 2)); // Test in 2 minutes
    await scheduleNotification(
      id: 999, // Test ID
      title: 'Test thông báo',
      body: message ?? 'Đây là thông báo test để kiểm tra tính năng!',
      scheduledDate: testTime,
    );
  }

  // Method for immediate notification (show now)
  Future<void> showImmediateTestNotification({String? message}) async {
    print('🔔 Showing immediate test notification');

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'pill_reminder_channel',
      'Pill Reminder',
      channelDescription: 'Channel for pill reminders',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableLights: true,
      enableVibration: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    try {
      await flutterLocalNotificationsPlugin.show(
        9999, // Different ID
        'THÔNG BÁO NGAY LẬP TỨC',
        message ?? 'Đây là thông báo TEST tức thì!',
        platformChannelSpecifics,
        payload: 'immediate_test',
      );
      print('✅ Immediate notification shown successfully');
    } catch (e) {
      print('❌ Error showing immediate notification: $e');
    }
  }
}
