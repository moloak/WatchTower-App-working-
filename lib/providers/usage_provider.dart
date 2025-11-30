import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_usage_model.dart';
import '../services/app_usage_service.dart';
import '../services/local_usage_storage.dart';
import '../services/notification_service.dart';
import '../services/background_service.dart';
import '../services/overlay_service.dart' show WarningLevel;

class UsageProvider extends ChangeNotifier {
  final AppUsageService _usageService = AppUsageService();
  
  AppUsageService get usageService => _usageService;
  final NotificationService _notificationService = NotificationService();
  
  Map<String, AppUsageModel> _monitoredApps = {};
  Map<String, Duration> _weeklyUsage = {};
  bool _isMonitoring = false;
  bool _hasPermissions = false;
  StreamSubscription<Map<String, AppUsageModel>>? _usageSubscription;
  Timer? _dailyResetTimer;

  Map<String, AppUsageModel> get monitoredApps => _monitoredApps;
  Map<String, Duration> get weeklyUsage => _weeklyUsage;
  bool get isMonitoring => _isMonitoring;
  bool get hasPermissions => _hasPermissions;
  
  /// Stream of usage updates for real-time UI rebuilds
  Stream<Map<String, AppUsageModel>> get usageStream => _usageService.usageStream;

  UsageProvider() {
    _initializeUsageMonitoring();
  }

  Future<void> _initializeUsageMonitoring() async {
    _hasPermissions = await _usageService.hasUsagePermission();
    
    // Initialize and request notification permissions for threshold alerts
    await _notificationService.initialize();
    await _notificationService.requestNotificationPermission();
    
    // Initialize local storage (sqlite) and restore monitored apps from Firestore
    await LocalUsageStorage.instance.init();

    // Initialize background worker which will attempt a weekly push when due.
    await BackgroundService().initialize(isInDebugMode: false);

    // If there is a weekly summary to push immediately (app opened), do it now
    await LocalUsageStorage.instance.pushWeeklySummaryIfDue();

    // Load any previously persisted monitored apps for the current user first
    await loadMonitoredAppsFromFirestore();

    // Set up daily reset timer
    _setupDailyResetTimer();

    // Debug forcing removed for production builds - monitoring will follow
    // only apps explicitly added via the Manage Apps screen.

    if (_hasPermissions) {
      await startMonitoring();
      
      // Immediately check thresholds when app opens to catch any notifications
      // that should have been shown while the app was closed
      debugPrint('UsageProvider: Running immediate threshold check on app startup');
      await _checkUsageThresholds();
    }
    
    _usageSubscription = _usageService.usageStream.listen((apps) async {
      _monitoredApps = apps;
      await _checkUsageThresholds();
      notifyListeners();
    });

    // Note: Overlay event listeners have been removed as overlays are no longer used.
    // Only notifications are used for usage warnings.
  }

  Future<bool> requestPermissions() async {
    _hasPermissions = await _usageService.requestPermissions();
    notifyListeners();
    
    if (_hasPermissions) {
      await startMonitoring();
    }
    return _hasPermissions;
  }

  /// Setup a daily timer to reset usage at midnight each day
  void _setupDailyResetTimer() {
    _dailyResetTimer?.cancel();
    
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);
    
    _dailyResetTimer = Timer(timeUntilMidnight, () async {
      // Reset at midnight
      await resetDailyUsage();
      debugPrint('UsageProvider: Daily reset executed at midnight');
      
      // Reschedule for next day
      _setupDailyResetTimer();
    });
  }

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    
    await _usageService.startMonitoring();
    _isMonitoring = true;
    notifyListeners();
  }

  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;
    
    await _usageService.stopMonitoring();
    _isMonitoring = false;
    notifyListeners();
  }

  /// Adds an InstalledApp to monitoring and persists the monitored app under
  /// the current user's Firestore document (subcollection `monitored_apps`).
  Future<void> addAppToMonitoring(InstalledApp installed, Duration dailyLimit) async {
    try {
      await _usageService.addAppToMonitoring(installed, dailyLimit);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final appUsage = _usageService.getAppUsage(installed.packageName);
        if (appUsage != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('monitored_apps')
              .doc(installed.packageName)
              .set(appUsage.toJson());
        }
      }
    } catch (e) {
        // ignore: avoid_print
        debugPrint('Error adding app to monitoring: $e');
    }
  }

  Future<void> removeAppFromMonitoring(String packageName) async {
    await _usageService.removeAppFromMonitoring(packageName);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('monitored_apps')
            .doc(packageName)
            .delete();
      } catch (e) {
          // ignore: avoid_print
          debugPrint('Failed to remove monitored app from Firestore: $e');
      }
    }
  }

  Future<void> updateAppLimit(String packageName, Duration newLimit) async {
    await _usageService.updateAppLimit(packageName, newLimit);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('monitored_apps')
            .doc(packageName)
            .update({'dailyLimit': newLimit.inMinutes});
      } catch (e) {
          // ignore: avoid_print
          debugPrint('Failed to update app limit in Firestore: $e');
      }
    }
  }

  Future<void> resetDailyUsage() async {
    await _usageService.resetDailyUsage();
  }

  Future<void> loadWeeklyUsage() async {
    _weeklyUsage = await _usageService.getWeeklyUsageStats();
    notifyListeners();
  }

  /// Load monitored apps persisted for the current user from Firestore and
  /// re-register them with the usage service so icons/limits are restored.
  Future<void> loadMonitoredAppsFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('monitored_apps')
          .get();

      for (final doc in snapshot.docs) {
        try {
          final appModel = AppUsageModel.fromJson(doc.data());
          // Re-create an InstalledApp so the service can register it and keep
          // using its internal icon- and usage-updating logic.
          final installed = InstalledApp(
            packageName: appModel.packageName,
            appName: appModel.appName,
            apkFilePath: appModel.iconPath,
            iconBytes: appModel.iconBytes,
          );

          await _usageService.addAppToMonitoring(installed, appModel.dailyLimit);
        } catch (e) {
          // ignore individual doc errors
          // ignore: avoid_print
            debugPrint('Failed to restore monitored app ${doc.id}: $e');
        }
      }
    } catch (e) {
        // ignore: avoid_print
        debugPrint('Error loading monitored apps from Firestore: $e');
    }
  }

  /// Debug helper: when in debug builds, force the first monitored app through
  /// 90% then 100% to exercise threshold logic. No-op if there are no monitored apps.
  // debug helper removed

  Future<void> _checkUsageThresholds() async {
    for (final app in _monitoredApps.values) {
      try {
        final percentage = app.cappedUsagePercentage;
        debugPrint('UsageProvider: Checking ${app.packageName}: ${percentage.toStringAsFixed(1)}% (notified: 30=${app.notified30}, 60=${app.notified60}, 90=${app.notified90})');
        
        // Reset flags when usage drops below thresholds (to allow re-triggering when usage increases again)
        if (percentage < 30 && app.notified30) {
          debugPrint('UsageProvider: Usage for ${app.packageName} dropped below 30%, resetting notification flag');
          await _usageService.markAppState(app.packageName, notified30: false);
        }
        if (percentage < 60 && app.notified60) {
          debugPrint('UsageProvider: Usage for ${app.packageName} dropped below 60%, resetting notification flag');
          await _usageService.markAppState(app.packageName, notified60: false);
        }
        if (percentage < 90 && app.notified90) {
          debugPrint('UsageProvider: Usage for ${app.packageName} dropped below 90%, resetting notification flag');
          await _usageService.markAppState(app.packageName, notified90: false);
        }
        
        // 90% threshold: show final warning (check first since it's highest priority)
        if (percentage >= 90 && !app.notified90) {
          debugPrint('UsageProvider: 90% threshold reached for ${app.packageName} (${percentage.toStringAsFixed(1)}%)');
          await _showUsageWarning(app, WarningLevel.ninetyPercent);
          await _usageService.markAppState(app.packageName, notified90: true);
          continue;
        }

        // 60% threshold
        if (percentage >= 60 && !app.notified60) {
          debugPrint('UsageProvider: 60% threshold reached for ${app.packageName} (${percentage.toStringAsFixed(1)}%)');
          await _showUsageWarning(app, WarningLevel.sixtyPercent);
          await _usageService.markAppState(app.packageName, notified60: true);
          continue;
        }

        // 30% threshold
        if (percentage >= 30 && !app.notified30) {
          debugPrint('UsageProvider: 30% threshold reached for ${app.packageName} (${percentage.toStringAsFixed(1)}%)');
          await _showUsageWarning(app, WarningLevel.thirtyPercent);
          await _usageService.markAppState(app.packageName, notified30: true);
          continue;
        }
      } catch (e) {
        // avoid crashing the monitoring loop on one bad app
        debugPrint('Error checking thresholds for ${app.packageName}: $e');
      }
    }
  }

  Future<void> _showUsageWarning(AppUsageModel app, WarningLevel level) async {
    // Show notification only - overlays have been removed
    await _notificationService.showUsageWarningNotification(app, level);
  }

  List<AppUsageModel> getAppsAtThreshold(double threshold) {
    return _monitoredApps.values.where((app) {
      final percentage = app.cappedUsagePercentage;
      return percentage >= threshold && percentage < (threshold + 10);
    }).toList();
  }

  List<AppUsageModel> getTopUsedApps({int limit = 5}) {
    final sortedApps = _monitoredApps.values.toList()
      ..sort((a, b) => b.currentUsage.compareTo(a.currentUsage));
    
    return sortedApps.take(limit).toList();
  }

  Duration getTotalDailyUsage() {
    return _monitoredApps.values.fold(
      Duration.zero,
      (total, app) => total + app.currentUsage,
    );
  }

  Duration getTotalWeeklyUsage() {
    return _weeklyUsage.values.fold(
      Duration.zero,
      (total, usage) => total + usage,
    );
  }

  Map<String, double> getUsagePercentages() {
    final totalUsage = getTotalDailyUsage();
    if (totalUsage.inSeconds == 0) return {};

    return _monitoredApps.map((packageName, app) {
      final percentage = (app.currentUsage.inSeconds / totalUsage.inSeconds) * 100;
      return MapEntry(packageName, percentage);
    });
  }

  List<AppUsageModel> getOverusedApps() {
    return _monitoredApps.values.where((app) => app.isAt100Percent).toList();
  }

  List<AppUsageModel> getAppsNearLimit() {
    return _monitoredApps.values.where((app) =>
      app.cappedUsagePercentage >= 80 && app.cappedUsagePercentage < 100
    ).toList();
  }

  @override
  void dispose() {
    _usageSubscription?.cancel();
    _dailyResetTimer?.cancel();
    _usageService.dispose();
    super.dispose();
  }
}

