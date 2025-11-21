import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'package:firebase_core/firebase_core.dart';
import '../services/local_usage_storage.dart';

const String weeklySummaryTask = 'weekly_summary_task';
const String appMonitoringTask = 'app_monitoring_task';

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

    // Get all monitored apps and check thresholds
    // This task runs periodically even when the app is closed
    debugPrint('[BackgroundService] Running app monitoring in background');

    // Note: In a background isolate, we can't directly access UI state.
    // The actual threshold checking and notification showing is coordinated
    // by the app when it's running. This task mainly keeps usage data fresh.
  } catch (e) {
    debugPrint('Background app monitoring failed: $e');
  }
}

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
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Failed to initialize BackgroundService: $e');
    }
  }
}
