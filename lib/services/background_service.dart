import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/local_usage_storage.dart';
import '../services/notification_service.dart';
import '../services/overlay_service.dart';
import '../models/app_usage_model.dart';

const String weeklySummaryTask = 'weekly_summary_task';
const String appMonitoringTask = 'app_monitoring_task';
const String thresholdCheckTask = 'threshold_check_task';

/// Callback dispatcher run in background isolate by Workmanager.
@pragma('vm:entry-point')
void callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // Initialize Firebase in the background isolate
      await Firebase.initializeApp();
    } catch (_) {
      // ignore init errors here
    }

    // Handle both weekly summary and app monitoring tasks
    if (task == weeklySummaryTask) {
      await _handleWeeklySummary();
    } else if (task == appMonitoringTask) {
      await _handleAppMonitoring();
    } else if (task == thresholdCheckTask) {
      await _handleThresholdCheck();
    }

    return Future.value(true);
  });
}

Future<void> _handleWeeklySummary() async {
  try {
    await LocalUsageStorage.instance.init();
    await LocalUsageStorage.instance.pushWeeklySummaryIfDue();
  } catch (e) {
    debugPrint('Background weekly summary failed: $e');
  }
}

Future<void> _handleAppMonitoring() async {
  try {
    await LocalUsageStorage.instance.init();
    debugPrint('[BackgroundService] Running app monitoring in background');
    // Usage data is continuously tracked by the OS; this just ensures data is persisted
  } catch (e) {
    debugPrint('Background app monitoring failed: $e');
  }
}

/// Continuously check thresholds even when app is closed
Future<void> _handleThresholdCheck() async {
  try {
    await LocalUsageStorage.instance.init();
    await NotificationService().initialize();
    
    debugPrint('[BackgroundService] Checking usage thresholds...');
    
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final dateStr = _formatDate(now);
    
    // Scan for monitored apps and check thresholds
    await _checkAllMonitoredAppsThresholds(prefs, dateStr);
    
  } catch (e) {
    debugPrint('Background threshold check failed: $e');
  }
}

/// Check thresholds for all monitored apps
Future<void> _checkAllMonitoredAppsThresholds(SharedPreferences prefs, String dateStr) async {
  try {
    // Get daily usage for today
    final allUsage = await LocalUsageStorage.instance.getDailyUsageForDate(dateStr);
    
    for (final appUsageMap in allUsage) {
      try {
        final packageName = appUsageMap['packageName'] as String;
        final appName = appUsageMap['appName'] as String? ?? '';
        final currentUsageMinutes = appUsageMap['minutes'] as int? ?? 0;
        final dailyLimitMinutes = appUsageMap['dailyLimit'] as int? ?? 60;
        
        if (dailyLimitMinutes == 0) continue;
        
        final percentage = ((currentUsageMinutes / dailyLimitMinutes) * 100).toInt();
        
        // Keys for tracking which notifications have been shown
        final today30Key = 'notified_30_${packageName}_$dateStr';
        final today60Key = 'notified_60_${packageName}_$dateStr';
        final today90Key = 'notified_90_${packageName}_$dateStr';
        
        // Check and show notification for first threshold reached
        if (percentage >= 30 && percentage < 60) {
          if (!(prefs.getBool(today30Key) ?? false)) {
            await _showThresholdNotification(packageName, appName, 30, percentage);
            await prefs.setBool(today30Key, true);
            debugPrint('[BackgroundService] Notified $appName at 30% threshold');
          }
        } else if (percentage >= 60 && percentage < 90) {
          if (!(prefs.getBool(today60Key) ?? false)) {
            await _showThresholdNotification(packageName, appName, 60, percentage);
            await prefs.setBool(today60Key, true);
            debugPrint('[BackgroundService] Notified $appName at 60% threshold');
          }
        } else if (percentage >= 90) {
          if (!(prefs.getBool(today90Key) ?? false)) {
            await _showThresholdNotification(packageName, appName, 90, percentage);
            await prefs.setBool(today90Key, true);
            debugPrint('[BackgroundService] Notified $appName at 90% threshold');
          }
        }
      } catch (error) {
        debugPrint('[BackgroundService] Error checking app threshold: $error');
      }
    }
  } catch (error) {
    debugPrint('[BackgroundService] Error in _checkAllMonitoredAppsThresholds: $error');
  }
}

/// Show threshold notification with heads-up display
Future<void> _showThresholdNotification(
  String packageName, 
  String appName, 
  int threshold, 
  int currentPercentage
) async {
  try {
    final notificationService = NotificationService();
    await notificationService.initialize();
    
    final warningLevel = threshold == 30 
        ? WarningLevel.thirtyPercent
        : threshold == 60 
            ? WarningLevel.sixtyPercent 
            : WarningLevel.ninetyPercent;
    
    // Create temp app model for notification
    final tempApp = AppUsageModel(
      packageName: packageName,
      appName: appName,
      iconPath: '',
      dailyLimit: const Duration(hours: 1),
      currentUsage: Duration(minutes: currentPercentage),
      isMonitored: true,
      lastUsed: DateTime.now(),
    );
    
    await notificationService.showUsageWarningNotification(tempApp, warningLevel);
    debugPrint('[BackgroundService] Showed $threshold% notification for $appName');
  } catch (e) {
    debugPrint('[BackgroundService] Error showing notification: $e');
  }
}

String _formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  /// Initialize Workmanager and register the periodic weekly task and app monitoring task.
  Future<void> initialize({bool isInDebugMode = false}) async {
    try {
      wm.Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: isInDebugMode,
      );

      // Register a periodic task for weekly summary (network required)
      await wm.Workmanager().registerPeriodicTask(
        'weekly-summary-unique-id',
        weeklySummaryTask,
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(minutes: 5),
        constraints: wm.Constraints(networkType: wm.NetworkType.connected),
      );

      // Register a periodic task for app monitoring (no network required, every 30 minutes)
      await wm.Workmanager().registerPeriodicTask(
        'app-monitoring-unique-id',
        appMonitoringTask,
        frequency: const Duration(minutes: 30),
        initialDelay: const Duration(minutes: 5),
      );

      // Register a frequent threshold check task (runs every 15 minutes)
      // This ensures real-time notifications even when app is closed/backgrounded
      await wm.Workmanager().registerPeriodicTask(
        'threshold-check-unique-id',
        thresholdCheckTask,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 1),
      );

      // Immediately check thresholds on startup to catch any notifications missed
      // if the app hasn't been opened since the last threshold was reached
      debugPrint('[BackgroundService] Running immediate threshold check on startup');
      await _handleThresholdCheck();

      debugPrint('[BackgroundService] Successfully initialized all background tasks');
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Failed to initialize BackgroundService: $e');
    }
  }
}
