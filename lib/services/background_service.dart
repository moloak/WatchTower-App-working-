import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/local_usage_storage.dart';

const String weeklySummaryTask = 'weekly_summary_task';

/// Callback dispatcher run in background isolate by Workmanager.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      // Initialize Firebase in the background isolate. If this fails the
      // LocalUsageStorage.pushWeeklySummaryIfDue will simply return early
      // because it requires an authenticated user.
      await Firebase.initializeApp();
    } catch (_) {
      // ignore init errors here; we'll still attempt to use local storage.
    }

    try {
      await LocalUsageStorage.instance.init();

      // Only attempt to push summary if there's at least one app with usage
      // in the week. LocalUsageStorage.pushWeeklySummaryIfDue() performs
      // an internal check and will no-op if already pushed or no uid.
      await LocalUsageStorage.instance.pushWeeklySummaryIfDue();
    } catch (e) {
      // best-effort background work. Do not crash.
      // ignore: avoid_print
      debugPrint('Background weekly summary failed: $e');
    }

    return Future.value(true);
  });
}

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  /// Initialize Workmanager and register the periodic weekly task.
  Future<void> initialize({bool isInDebugMode = false}) async {
    try {
      Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: isInDebugMode,
      );

      // Register a periodic task. Workmanager on Android requires a minimum
      // frequency; here we register a daily check and the job will only push
      // when the week-end condition is met by LocalUsageStorage.
      await Workmanager().registerPeriodicTask(
        'weekly-summary-unique-id',
        weeklySummaryTask,
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(minutes: 5),
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Failed to initialize BackgroundService: $e');
    }
  }
}
