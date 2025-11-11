import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_usage_model.dart';
import '../services/app_usage_service.dart';
import '../services/local_usage_storage.dart';
import '../services/overlay_service.dart';
import '../services/notification_service.dart';
import '../services/background_service.dart';

class UsageProvider extends ChangeNotifier {
  final AppUsageService _usageService = AppUsageService();
  
  AppUsageService get usageService => _usageService;
  final OverlayService _overlayService = OverlayService();
  final NotificationService _notificationService = NotificationService();
  
  Map<String, AppUsageModel> _monitoredApps = {};
  Map<String, Duration> _weeklyUsage = {};
  bool _isMonitoring = false;
  bool _hasPermissions = false;
  StreamSubscription<Map<String, AppUsageModel>>? _usageSubscription;

  Map<String, AppUsageModel> get monitoredApps => _monitoredApps;
  Map<String, Duration> get weeklyUsage => _weeklyUsage;
  bool get isMonitoring => _isMonitoring;
  bool get hasPermissions => _hasPermissions;

  UsageProvider() {
    _initializeUsageMonitoring();
  }

  Future<void> _initializeUsageMonitoring() async {
    _hasPermissions = await _usageService.hasUsagePermission();
    
    // Initialize local storage (sqlite) and restore monitored apps from Firestore
    await LocalUsageStorage.instance.init();

    // Initialize background worker which will attempt a weekly push when due.
    await BackgroundService().initialize(isInDebugMode: false);

    // If there is a weekly summary to push immediately (app opened), do it now
    await LocalUsageStorage.instance.pushWeeklySummaryIfDue();

    // Load any previously persisted monitored apps for the current user first
    await loadMonitoredAppsFromFirestore();

    // Debug forcing removed for production builds - monitoring will follow
    // only apps explicitly added via the Manage Apps screen.

    if (_hasPermissions) {
      await startMonitoring();
    }
    
    _usageSubscription = _usageService.usageStream.listen((apps) async {
      _monitoredApps = apps;
      await _checkUsageThresholds();
      notifyListeners();
    });

    // Listen for overlay events (locks, countdown completion, manual dismiss)
    _overlayService.overlayStream.listen((event) async {
      try {
        if (event.type == OverlayEventType.appLock && event.app != null) {
          // Record lock start time and set isLocked flag
          await _usageService.markAppState(event.app!.packageName,
              isLocked: true, lockStartTime: event.timestamp);
        } else if (event.type == OverlayEventType.overlayHidden) {
            // If an explicit packageName was provided by the platform, compute
            // overshot only for that app. Otherwise fall back to clearing all
            // currently locked apps (legacy behavior).
            final now = DateTime.now();
            final pkg = event.packageName;
            if (pkg != null && _monitoredApps.containsKey(pkg)) {
              final app = _monitoredApps[pkg]!;
              final lockStart = app.lockStartTime ?? now;
              final overshot = now.difference(lockStart);
              final newOvershot = app.overshotDuration + overshot;
              await _usageService.markAppState(app.packageName,
                  isLocked: false, overshotDuration: newOvershot, lockStartTime: null);
            } else {
              for (final app in _monitoredApps.values.where((a) => a.isLocked)) {
                final lockStart = app.lockStartTime ?? now;
                final overshot = now.difference(lockStart);
                final newOvershot = app.overshotDuration + overshot;
                await _usageService.markAppState(app.packageName,
                    isLocked: false, overshotDuration: newOvershot, lockStartTime: null);
              }
            }
        } else if (event.type == OverlayEventType.countdownComplete && event.app != null) {
          // Countdown finished -- show the app lock and record state
          await _showAppLock(event.app!);
          await _usageService.markAppState(event.app!.packageName,
              isLocked: true, lockStartTime: DateTime.now());
        }
      } catch (e) {
          // ignore overlay handling errors
          debugPrint('Overlay event handling error: $e');
      }
    });
  }

  Future<bool> requestPermissions() async {
    _hasPermissions = await _usageService.requestPermissions();
    notifyListeners();
    
    if (_hasPermissions) {
      await startMonitoring();
    }
    return _hasPermissions;
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
        // 30% threshold
        if (app.isAt30Percent && !app.notified30) {
            debugPrint('UsageProvider: 30% threshold reached for ${app.packageName} (${app.cappedUsagePercentage.toStringAsFixed(1)}%)');
          await _showUsageWarning(app, WarningLevel.thirtyPercent);
          await _usageService.markAppState(app.packageName, notified30: true);
          continue;
        }

        // 60% threshold
        if (app.isAt60Percent && !app.notified60) {
            debugPrint('UsageProvider: 60% threshold reached for ${app.packageName} (${app.cappedUsagePercentage.toStringAsFixed(1)}%)');
          await _showUsageWarning(app, WarningLevel.sixtyPercent);
          await _usageService.markAppState(app.packageName, notified60: true);
          continue;
        }

        // 90% threshold: start countdown to lock and notify once
        if (app.isAt90Percent && !app.notified90) {
            debugPrint('UsageProvider: 90% threshold reached for ${app.packageName} (${app.cappedUsagePercentage.toStringAsFixed(1)}%) - starting countdown');
          await _showUsageWarning(app, WarningLevel.ninetyPercent);
          await _usageService.markAppState(app.packageName, notified90: true);

          // Start a countdown equal to the remaining time until 100%.
          final remaining = app.remainingTime;
          // If there's no measurable remaining time, lock immediately.
          _overlayService.startCountdown(remaining, app);
          continue;
        }

        // 100% reached: lock the app if not already locked
        if (app.isAt100Percent && !app.isLocked) {
            debugPrint('UsageProvider: 100% reached for ${app.packageName} - locking app');
          await _showAppLock(app);
          await _usageService.markAppState(app.packageName,
              isLocked: true, lockStartTime: DateTime.now());
          continue;
        }
      } catch (e) {
          // avoid crashing the monitoring loop on one bad app
          debugPrint('Error checking thresholds for ${app.packageName}: $e');
      }
    }
  }

  Future<void> _showUsageWarning(AppUsageModel app, WarningLevel level) async {
    // Show overlay warning
    await _overlayService.showUsageWarning(app, level);
    
    // Show notification
    await _notificationService.showUsageWarningNotification(app, level);
  }

  Future<void> _showAppLock(AppUsageModel app) async {
    // Show app lock overlay
    await _overlayService.showAppLockOverlay(app);
    
    // Show notification
    await _notificationService.showAppLockNotification(app);
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
    _usageService.dispose();
    _overlayService.dispose();
    super.dispose();
  }
}

