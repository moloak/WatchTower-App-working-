import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../models/app_usage_model.dart';
import '../models/user_model.dart';
import 'overlay_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _isInitialized = true;
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return false;
    }
  }

  Future<bool> hasNotificationPermission() async {
    try {
      return await Permission.notification.isGranted;
    } catch (e) {
      debugPrint('Error checking notification permission: $e');
      return false;
    }
  }

  Future<void> showUsageWarningNotification(AppUsageModel app, WarningLevel level) async {
    if (!await hasNotificationPermission()) return;

    final title = _getWarningTitle(level);
    final body = _getWarningBody(app, level);
    final id = _getNotificationId(app.packageName, level);

    // Configure Android notification to show on top of other apps with full screen intent
    // This ensures the notification appears as a heads-up notification even when another app is in foreground
    final androidDetails = AndroidNotificationDetails(
      'usage_warnings',
      'Usage Warning Notifications',
      channelDescription: 'Notifications for app usage warnings',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      fullScreenIntent: true,
      enableVibration: true,
      enableLights: true,
      color: Colors.deepOrange,
      onlyAlertOnce: false,
    );

    debugPrint('NotificationService: Showing heads-up notification for ${app.packageName} - $title: $body');
    await _notifications.show(id, title, body, NotificationDetails(android: androidDetails));
  }

  Future<void> showAppLockNotification(AppUsageModel app) async {
    if (!await hasNotificationPermission()) return;

    const title = 'App Locked';
    const body = 'You\'ve reached your daily usage limit. Take a break and come back fresh tomorrow.';
    final id = _getNotificationId(app.packageName, WarningLevel.ninetyPercent) + 1000;

    const androidDetails = AndroidNotificationDetails(
      'app_locks',
      'App Lock Notifications',
      channelDescription: 'Notifications when apps are locked',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      ongoing: true,
    );

  await _notifications.show(id, title, body, NotificationDetails(android: androidDetails));
  }

  Future<void> showWeeklyReportNotification(UserModel user, Map<String, Duration> weeklyUsage) async {
    if (!await hasNotificationPermission()) return;

    final aiAgent = user.selectedAiAgent;
    final title = 'Weekly Digital Wellness Report';
    final body = '$aiAgent has prepared your weekly usage report with personalized insights and tips for better digital wellness.';

    const androidDetails = AndroidNotificationDetails(
      'weekly_reports',
      'Weekly Report Notifications',
      channelDescription: 'Weekly digital wellness reports from your AI agent',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

  await _notifications.show(9999, title, body, NotificationDetails(android: androidDetails));
  }

  Future<void> showTrialReminderNotification(UserModel user) async {
    if (!await hasNotificationPermission()) return;

    final daysLeft = user.trialEndDate?.difference(DateTime.now()).inDays ?? 0;
    if (daysLeft <= 0) return;

    final title = 'Trial Ending Soon';
    final body = daysLeft == 1 
        ? 'Your free trial ends tomorrow! Subscribe now to continue your digital wellness journey.'
        : 'Your free trial ends in $daysLeft days. Subscribe now to continue your digital wellness journey.';

    const androidDetails = AndroidNotificationDetails(
      'trial_reminders',
      'Trial Reminder Notifications',
      channelDescription: 'Reminders about trial expiration',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

  await _notifications.show(9998, title, body, NotificationDetails(android: androidDetails));
  }

  Future<void> showSubscriptionExpiredNotification() async {
    if (!await hasNotificationPermission()) return;

    const title = 'Subscription Expired';
    const body = 'Your Watchtower subscription has expired. Renew now to continue monitoring your digital wellness.';

    await _notifications.show(9997, title, body, NotificationDetails(android: AndroidNotificationDetails(
      'subscription_alerts',
      'Subscription Alert Notifications',
      channelDescription: 'Alerts about subscription status',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    )));
  }

  Future<void> scheduleWeeklyReport() async {
    // Schedule weekly report for every Sunday at 9 PM
    // Calculate next Sunday at 9 PM
    final now = DateTime.now();
    final daysUntilSunday = (7 - now.weekday) % 7;
    final nextSunday = now.add(Duration(days: daysUntilSunday == 0 ? 7 : daysUntilSunday));
    final scheduledTime = DateTime(nextSunday.year, nextSunday.month, nextSunday.day, 21, 0);

    // TODO: Implement scheduled notifications with proper timezone handling
  debugPrint('Scheduled weekly report for: $scheduledTime');
  }

  Future<void> scheduleTrialReminders(UserModel user) async {
    if (user.trialEndDate == null) return;

    final trialEnd = user.trialEndDate!;
    final now = DateTime.now();
    
    // Schedule reminder 3 days before trial ends
    final reminderDate = trialEnd.subtract(const Duration(days: 3));
    if (reminderDate.isAfter(now)) {
      // TODO: Implement scheduled notifications with proper timezone handling
  debugPrint('Scheduled trial reminder for: $reminderDate');
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  String _getWarningTitle(WarningLevel level) {
    switch (level) {
      case WarningLevel.thirtyPercent:
        return 'Usage Alert - 30%';
      case WarningLevel.sixtyPercent:
        return 'Usage Alert - 60%';
      case WarningLevel.ninetyPercent:
        return 'Final Warning - 90%';
    }
  }

  String _getWarningBody(AppUsageModel app, WarningLevel level) {
    final remainingTime = app.remainingTime;
    final hours = remainingTime.inHours;
    final minutes = remainingTime.inMinutes % 60;

    switch (level) {
      case WarningLevel.thirtyPercent:
        return 'You\'ve used 30% of your daily limit for ${app.appName}. Time remaining: ${hours}h ${minutes}m';
      case WarningLevel.sixtyPercent:
        return 'You\'ve used 60% of your daily limit for ${app.appName}. Time remaining: ${hours}h ${minutes}m';
      case WarningLevel.ninetyPercent:
        return 'You\'ve used 90% of your daily limit for ${app.appName}. This is your final warning! Save your work now.';
    }
  }

  int _getNotificationId(String packageName, WarningLevel level) {
    final packageHash = packageName.hashCode;
    final levelValue = level.index;
    return (packageHash % 10000) + (levelValue * 1000);
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap
  debugPrint('Notification tapped: ${response.payload}');
  }
}

