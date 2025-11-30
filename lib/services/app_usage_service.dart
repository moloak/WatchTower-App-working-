import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:usage_stats/usage_stats.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_usage_model.dart';
import 'local_usage_storage.dart';
// Use installed_apps for Android installed-app enumeration
import 'package:installed_apps/installed_apps.dart' as ia;

// Mock class for AppInfo - replace with actual device_apps AppInfo in real implementation
class InstalledApp {
  final String packageName;
  final String appName;
  final String apkFilePath;
  final Uint8List? iconBytes;

  InstalledApp({
    required this.packageName,
    required this.appName,
    this.apkFilePath = '',
    this.iconBytes,
  });
}

class AppUsageService {
  static final AppUsageService _instance = AppUsageService._internal();
  factory AppUsageService() => _instance;
  AppUsageService._internal();

  /// Enable debug logging for usage queries and permission checks.
  bool debugLogging = false;

  void setDebugLogging(bool enabled) {
    debugLogging = enabled;
  }

  Timer? _usageTimer;
  final Map<String, AppUsageModel> _monitoredApps = {};
  final StreamController<Map<String, AppUsageModel>> _usageController = 
      StreamController<Map<String, AppUsageModel>>.broadcast();

  Stream<Map<String, AppUsageModel>> get usageStream => _usageController.stream;
  Map<String, AppUsageModel> get monitoredApps => Map.unmodifiable(_monitoredApps);

  Future<bool> requestPermissions() async {
    try {
      // On Android, prompt for Overlay permission and open Usage Access settings
      if (Platform.isAndroid) {
        // Request overlay/window permission first
        final overlayStatus = await Permission.systemAlertWindow.request();

        // Open Usage Access settings so user can grant access
        final intent = AndroidIntent(
          action: 'android.settings.USAGE_ACCESS_SETTINGS',
        );
        await intent.launch();

        // Wait up to 30 seconds for the user to grant Usage Access by polling
        final granted = await _waitForUsageAccess(timeout: const Duration(seconds: 30));

        return overlayStatus.isGranted && granted;
      }

      // Non-Android platforms: nothing to request here
      return true;
    } catch (e) {
  debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  /// Checks whether the app has Usage Access permission on Android.
  /// For Android we attempt a short UsageStats query; if it succeeds (no exception)
  /// and returns a list (possibly empty), we consider the permission granted.
  Future<bool> hasUsagePermission() async {
    try {
      if (Platform.isAndroid) {
        final now = DateTime.now();
        final from = now.subtract(const Duration(minutes: 1));
        final stats = await UsageStats.queryUsageStats(from, now);
        if (debugLogging) {
          debugPrint('[AppUsageService] hasUsagePermission: queried ${from.toIso8601String()} -> ${now.toIso8601String()}, result count=${stats.length}');
        }
        // If the call succeeds (even with empty list) we treat as access granted.
        return true;
      }

      // Non-Android platforms: assume granted/available
      return true;
    } catch (e) {
      // Query threw - likely missing permission
      return false;
    }
  }

  Future<bool> _waitForUsageAccess({required Duration timeout}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final ok = await hasUsagePermission();
      if (ok) return true;
      await Future.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  

  Future<List<InstalledApp>> getInstalledApps() async {
    try {
      if (Platform.isAndroid) {
        // Query installed apps using the installed_apps plugin.
        final apps = await ia.InstalledApps.getInstalledApps(
          // Include system apps so preinstalled apps like YouTube show up.
          excludeSystemApps: false,
          excludeNonLaunchableApps: true,
          withIcon: true,
        );

        // Filter out this app (Watchtower) and any internal/system entries
        final filtered = apps.where((a) {
          final pkg = a.packageName.toLowerCase();
          final name = a.name.toLowerCase();
          if (pkg.contains('com.example.project_1')) return false; // app id
          if (name.contains('watchtower')) return false; // app name
          return true;
        }).toList();

        return filtered.map((a) {
          return InstalledApp(
            packageName: a.packageName,
            appName: a.name,
            apkFilePath: '',
            iconBytes: a.icon,
          );
        }).toList();
      }

      // Non-Android platforms: return a small mock list
      return [
        InstalledApp(packageName: 'com.whatsapp', appName: 'WhatsApp'),
        InstalledApp(packageName: 'com.facebook.katana', appName: 'Facebook'),
        InstalledApp(packageName: 'com.instagram.android', appName: 'Instagram'),
      ];
    } catch (e) {
  debugPrint('Error getting installed apps: $e');
      return [];
    }
  }

  /// Try to find an installed app by its package name. Returns null if not found.
  Future<InstalledApp?> findInstalledAppByPackage(String packageName) async {
    try {
      if (Platform.isAndroid) {
        final apps = await ia.InstalledApps.getInstalledApps(
          excludeSystemApps: false,
          excludeNonLaunchableApps: false,
          withIcon: true,
        );

        for (final a in apps) {
          if (a.packageName.toLowerCase() == packageName.toLowerCase()) {
            return InstalledApp(
              packageName: a.packageName,
              appName: a.name,
              apkFilePath: '',
              iconBytes: a.icon,
            );
          }
        }
      }
    } catch (e) {
  debugPrint('Error finding installed app $packageName: $e');
    }

    return null;
  }

  Future<void> startMonitoring() async {
    if (_usageTimer?.isActive == true) return;

    _usageTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _updateUsageStats();
    });

    // Initial update
    await _updateUsageStats();
  }

  Future<void> stopMonitoring() async {
    _usageTimer?.cancel();
    _usageTimer = null;
  }

  Future<void> _updateUsageStats() async {
    try {
      final now = DateTime.now();
      
      for (final packageName in _monitoredApps.keys) {
        final app = _monitoredApps[packageName]!;
        // Query usage from when monitoring was triggered for this app
        final usageStats = await UsageStats.queryUsageStats(
          app.monitoringStartTime,
          now,
        );

        if (debugLogging) {
          debugPrint('[AppUsageService] _updateUsageStats: queried ${app.monitoringStartTime.toIso8601String()} -> ${now.toIso8601String()} for ${app.packageName}, found ${usageStats.length} records');
        }

        for (final stat in usageStats) {
          if (stat.packageName == packageName) {
            // The usage_stats plugin may return totalTimeInForeground as an int or a String
            // depending on platform/plugin version. Handle both safely.
            int millis = 0;
            try {
              final dynamic raw = stat.totalTimeInForeground;
              if (raw is int) {
                millis = raw;
              } else if (raw is String) {
                millis = int.tryParse(raw) ?? 0;
              } else {
                millis = int.tryParse(raw.toString()) ?? 0;
              }
            } catch (_) {
              millis = 0;
            }
            final currentUsage = Duration(milliseconds: millis);
            final updatedApp = app.copyWith(
              currentUsage: currentUsage,
              lastUsed: now,
            );

            _monitoredApps[packageName] = updatedApp;

            if (debugLogging) {
              debugPrint('[AppUsageService] updated ${updatedApp.packageName} -> current=${updatedApp.currentUsage.inMinutes}m (${updatedApp.cappedUsagePercentage.toStringAsFixed(1)}%) remaining=${updatedApp.remainingTime.inMinutes}m');
            }

            // Persist the daily usage locally so we can summarize later.
            try {
              final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
              await LocalUsageStorage.instance.saveDailyUsage(dateStr, updatedApp);
            } catch (e) {
              // ignore: avoid_print
              debugPrint('Failed to persist daily usage: $e');
            }
            break;
          }
        }
      }

      _usageController.add(_monitoredApps);
    } catch (e) {
  debugPrint('Error updating usage stats: $e');
    }
  }

  /// Debug helper: run an immediate usage query for a custom range and print results.
  Future<void> debugDumpUsageNow({Duration lookback = const Duration(hours: 24)}) async {
    try {
      final now = DateTime.now();
      final from = now.subtract(lookback);
      final stats = await UsageStats.queryUsageStats(from, now);
  debugPrint('[AppUsageService] debugDumpUsageNow: ${from.toIso8601String()} -> ${now.toIso8601String()}, count=${stats.length}');
      for (final s in stats) {
  debugPrint('[AppUsageService] USAGE ${s.packageName} totalForeground=${s.totalTimeInForeground} lastTime=${s.lastTimeUsed}');
      }
    } catch (e) {
  debugPrint('[AppUsageService] debugDumpUsageNow error: $e');
    }
  }

  Future<void> addAppToMonitoring(InstalledApp appInfo, Duration dailyLimit) async {
    try {
      // Cap maximum allowed monitoring duration to 12 hours to avoid
      // accidental long-running monitoring sessions.
      final maxLimit = const Duration(hours: 12);
      final cappedLimit = dailyLimit > maxLimit ? maxLimit : dailyLimit;
      final appUsage = AppUsageModel(
        packageName: appInfo.packageName,
        appName: appInfo.appName,
        // Populate raw icon bytes when available so the UI can render them.
        iconBytes: appInfo.iconBytes,
        iconPath: appInfo.apkFilePath,
  dailyLimit: cappedLimit,
        currentUsage: Duration.zero,
        isMonitored: true,
        lastUsed: DateTime.now(),
        // notification/lock flags: start unset
        notified30: false,
        notified60: false,
        notified90: false,
        isLocked: false,
        overshotDuration: Duration.zero,
        lockStartTime: null,
      );

      _monitoredApps[appInfo.packageName] = appUsage;
      _usageController.add(_monitoredApps);
    } catch (e) {
  debugPrint('Error adding app to monitoring: $e');
    }
  }

  Future<void> removeAppFromMonitoring(String packageName) async {
    _monitoredApps.remove(packageName);
    _usageController.add(_monitoredApps);
  }

  Future<void> updateAppLimit(String packageName, Duration newLimit) async {
    if (_monitoredApps.containsKey(packageName)) {
      final app = _monitoredApps[packageName]!;
      final maxLimit = const Duration(hours: 12);
      final capped = newLimit > maxLimit ? maxLimit : newLimit;
      // Reset notification flags when limit is updated so new notifications can be triggered
      _monitoredApps[packageName] = app.copyWith(
        dailyLimit: capped,
        notified30: false,
        notified60: false,
        notified90: false,
      );
      _usageController.add(_monitoredApps);
      debugPrint('Updated app limit for $packageName to ${capped.inMinutes}m and reset notification flags');
    }
  }

  Future<void> resetDailyUsage() async {
    debugPrint('[AppUsageService] Resetting daily usage and notification flags for all monitored apps');
    
    for (final packageName in _monitoredApps.keys) {
      final app = _monitoredApps[packageName]!;
      _monitoredApps[packageName] = app.copyWith(
        currentUsage: Duration.zero,
        lastUsed: DateTime.now(),
        // Reset notification state each day
        notified30: false,
        notified60: false,
        notified90: false,
      );
      debugPrint('[AppUsageService] Reset flags for $packageName - ready for new threshold notifications');
    }
    
    // Also clear old notification keys from SharedPreferences to keep it clean
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final now = DateTime.now();
      final dateStr = _formatDate(now);
      
      // Remove yesterday's notification flags to keep SharedPreferences clean
      for (final key in keys) {
        if (key.startsWith('notified_') && !key.endsWith(dateStr)) {
          await prefs.remove(key);
          debugPrint('[AppUsageService] Cleaned old notification key: $key');
        }
      }
    } catch (e) {
      debugPrint('[AppUsageService] Error cleaning notification keys: $e');
    }
    
    _usageController.add(_monitoredApps);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Get the package name of the app currently in foreground
  /// Returns the package name of the most recently used app in the last minute
  Future<String?> getCurrentForegroundApp() async {
    try {
      if (Platform.isAndroid) {
        final now = DateTime.now();
        final from = now.subtract(const Duration(minutes: 1));
        final stats = await UsageStats.queryUsageStats(from, now);
        
        if (stats.isEmpty) return null;
        
        // Since UsageStats doesn't directly expose lastTimeUsed,
        // we'll query a very short time window and assume the most recent stat
        // is the current foreground app. UsageStats should return apps in reverse
        // chronological order, so we take the first one.
        if (stats.isNotEmpty) {
          return stats.first.packageName;
        }
      }
    } catch (e) {
      debugPrint('Error getting foreground app: $e');
    }
    return null;
  }

  /// Mark notification/lock state for a monitored app. This is used by the
  /// provider when a threshold notification or lock state changes so that the
  /// same event isn't repeated on each polling interval.
  Future<void> markAppState(
    String packageName, {
    bool? notified30,
    bool? notified60,
    bool? notified90,
  }) async {
    try {
      if (!_monitoredApps.containsKey(packageName)) return;
      final app = _monitoredApps[packageName]!;
      final updated = app.copyWith(
        notified30: notified30 ?? app.notified30,
        notified60: notified60 ?? app.notified60,
        notified90: notified90 ?? app.notified90,
      );

      _monitoredApps[packageName] = updated;
      _usageController.add(_monitoredApps);

      // Persist the updated app state to local storage as well
      try {
        final now = DateTime.now();
        final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        await LocalUsageStorage.instance.saveDailyUsage(dateStr, updated);
      } catch (_) {
        // don't block on storage errors
      }
    } catch (e) {
  debugPrint('Error marking app state for $packageName: $e');
    }
  }

  AppUsageModel? getAppUsage(String packageName) {
    return _monitoredApps[packageName];
  }

  List<AppUsageModel> getAppsAtThreshold(double threshold) {
    return _monitoredApps.values.where((app) {
      final percentage = app.cappedUsagePercentage;
      return percentage >= threshold && percentage < (threshold + 10);
    }).toList();
  }

  List<AppUsageModel> getAppsAt30Percent() => getAppsAtThreshold(30);
  List<AppUsageModel> getAppsAt60Percent() => getAppsAtThreshold(60);
  List<AppUsageModel> getAppsAt90Percent() => getAppsAtThreshold(90);
  List<AppUsageModel> getAppsAt100Percent() => getAppsAtThreshold(100);

  Future<Map<String, Duration>> getWeeklyUsageStats() async {
    try {
      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 7));

      final usageStats = await UsageStats.queryUsageStats(
        startOfWeek,
        endOfWeek,
      );

      final weeklyUsage = <String, Duration>{};
      for (final stat in usageStats) {
        if (stat.packageName != null && _monitoredApps.containsKey(stat.packageName)) {
          // Safely parse totalTimeInForeground to int millis
          int wmillis = 0;
          try {
            final dynamic raw = stat.totalTimeInForeground;
            if (raw is int) {
              wmillis = raw;
            } else if (raw is String) {
              wmillis = int.tryParse(raw) ?? 0;
            } else {
              wmillis = int.tryParse(raw.toString()) ?? 0;
            }
          } catch (_) {
            wmillis = 0;
          }
          weeklyUsage[stat.packageName!] = Duration(milliseconds: wmillis);
        }
      }

      return weeklyUsage;
    } catch (e) {
  debugPrint('Error getting weekly usage stats: $e');
      return {};
    }
  }

  /// Debug helper: force-update an app's current usage value. This is
  /// Intelligently reset notification flags based on new usage percentage.
  /// When usage is updated, we should notify only for thresholds that haven't been hit yet.
  /// For example, if current usage is 50%, we should reset flags for 60% and 90% so those
  /// notifications can be shown next time we reach those percentages.
  Map<String, bool> _calculateNotificationFlagsForUsage(AppUsageModel app, Duration newUsage) {
    final newPercentage = (newUsage.inSeconds / app.dailyLimit.inSeconds * 100).clamp(0.0, 100.0);
    
    // Determine which thresholds are still ahead of current usage
    final shouldNotify30 = newPercentage >= 30;
    final shouldNotify60 = newPercentage >= 60;
    final shouldNotify90 = newPercentage >= 90;
    
    // If a threshold hasn't been hit yet, reset its flag so we can notify
    final resetNotified30 = !shouldNotify30 ? false : (newPercentage < 60 ? app.notified30 : true);
    final resetNotified60 = !shouldNotify60 ? false : (newPercentage < 90 ? app.notified60 : true);
    final resetNotified90 = !shouldNotify90 ? false : app.notified90;
    
    debugPrint('_calculateNotificationFlagsForUsage: ${app.packageName} usage=${newPercentage.toStringAsFixed(1)}% flags: notified30=$resetNotified30, notified60=$resetNotified60, notified90=$resetNotified90');
    
    return {
      'notified30': resetNotified30,
      'notified60': resetNotified60,
      'notified90': resetNotified90,
    };
  }

  /// intended for developer testing only so we can simulate thresholds.
  Future<void> forceSetCurrentUsage(String packageName, Duration usage) async {
    try {
      if (!_monitoredApps.containsKey(packageName)) return;
      final now = DateTime.now();
      final app = _monitoredApps[packageName]!;
      
      // Intelligently reset notification flags based on new usage
      final notificationFlags = _calculateNotificationFlagsForUsage(app, usage);
      
      final updated = app.copyWith(
        currentUsage: usage,
        lastUsed: now,
        notified30: notificationFlags['notified30'] as bool,
        notified60: notificationFlags['notified60'] as bool,
        notified90: notificationFlags['notified90'] as bool,
      );
      _monitoredApps[packageName] = updated;
      _usageController.add(_monitoredApps);

      // Persist the updated usage for today's date
      try {
        final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        await LocalUsageStorage.instance.saveDailyUsage(dateStr, updated);
      } catch (_) {
        // ignore
      }
    } catch (e) {
  debugPrint('forceSetCurrentUsage error for $packageName: $e');
    }
  }

  void dispose() {
    _usageTimer?.cancel();
    _usageController.close();
  }
}
