import 'dart:typed_data';
import 'dart:convert';

class AppUsageModel {
  final String packageName;
  final String appName;
  // Optional raw icon bytes for displaying app icons in the UI. Not all
  // platforms or calls will populate this; fall back to an icon when null.
  final Uint8List? iconBytes;
  final String iconPath;
  final Duration dailyLimit;
  final Duration currentUsage;
  final bool isMonitored;
  final DateTime lastUsed;
  // Notification / lock state to avoid spamming the user repeatedly for the
  // same threshold. These are persisted so app restarts retain state.
  final bool notified30;
  final bool notified60;
  final bool notified90;
  // Whether the app is currently locked by Watchtower overlay
  final bool isLocked;
  // Total overshot duration accumulated when user manually overrides the
  // overlay and continues using the app past the daily limit.
  final Duration overshotDuration;
  // Timestamp when the app lock was started (used to compute overshot)
  final DateTime? lockStartTime;
  // Timestamp when monitoring was triggered for this app
  final DateTime monitoringStartTime;
  final List<UsageSession> sessions;

  AppUsageModel({
    required this.packageName,
    required this.appName,
    this.iconBytes,
    required this.iconPath,
    required this.dailyLimit,
    required this.currentUsage,
    required this.isMonitored,
    required this.lastUsed,
    this.sessions = const [],
    this.notified30 = false,
    this.notified60 = false,
    this.notified90 = false,
    this.isLocked = false,
    this.overshotDuration = Duration.zero,
    this.lockStartTime,
    DateTime? monitoringStartTime,
  }) : monitoringStartTime = monitoringStartTime ?? DateTime.now();

  double get usagePercentage {
    if (dailyLimit.inSeconds <= 0) return 0.0;
    if (currentUsage.inSeconds <= 0) return 0.0;
    return (currentUsage.inSeconds / dailyLimit.inSeconds) * 100.0;
  }

  // Ensure percentage is within 0..100 to avoid invalid progress values
  double get cappedUsagePercentage {
    final pct = usagePercentage;
    if (pct.isNaN) return 0.0;
    if (pct.isInfinite) return 100.0;
    return pct.clamp(0.0, 100.0);
  }

  bool get isAt30Percent => cappedUsagePercentage >= 30 && cappedUsagePercentage < 60;
  bool get isAt60Percent => cappedUsagePercentage >= 60 && cappedUsagePercentage < 90;
  bool get isAt90Percent => cappedUsagePercentage >= 90 && cappedUsagePercentage < 100;
  bool get isAt100Percent => cappedUsagePercentage >= 100;

  Duration get remainingTime {
    final duration = dailyLimit - currentUsage;
    // Ensure remaining time never goes below zero to show "0h 0m" when limit is reached
    return duration.isNegative ? Duration.zero : duration;
  }
  bool get hasTimeRemaining => remainingTime.inMinutes > 0;

  AppUsageModel copyWith({
    String? packageName,
    String? appName,
    Uint8List? iconBytes,
    String? iconPath,
    Duration? dailyLimit,
    Duration? currentUsage,
    bool? isMonitored,
    DateTime? lastUsed,
    List<UsageSession>? sessions,
    bool? notified30,
    bool? notified60,
    bool? notified90,
    bool? isLocked,
    Duration? overshotDuration,
    DateTime? lockStartTime,
    DateTime? monitoringStartTime,
  }) {
    return AppUsageModel(
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      iconBytes: iconBytes ?? this.iconBytes,
      iconPath: iconPath ?? this.iconPath,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      currentUsage: currentUsage ?? this.currentUsage,
      isMonitored: isMonitored ?? this.isMonitored,
      lastUsed: lastUsed ?? this.lastUsed,
      sessions: sessions ?? this.sessions,
      notified30: notified30 ?? this.notified30,
      notified60: notified60 ?? this.notified60,
      notified90: notified90 ?? this.notified90,
      isLocked: isLocked ?? this.isLocked,
      overshotDuration: overshotDuration ?? this.overshotDuration,
      lockStartTime: lockStartTime ?? this.lockStartTime,
      monitoringStartTime: monitoringStartTime ?? this.monitoringStartTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'appName': appName,
      'iconPath': iconPath,
      // If icon bytes are present, include as base64 so it can be persisted.
      if (iconBytes != null) 'iconBase64': base64Encode(iconBytes!),
      'dailyLimit': dailyLimit.inMinutes,
      'currentUsage': currentUsage.inMinutes,
      'isMonitored': isMonitored,
      'notified30': notified30,
      'notified60': notified60,
      'notified90': notified90,
      'isLocked': isLocked,
      'overshotDuration': overshotDuration.inMinutes,
      'lockStartTime': lockStartTime?.toIso8601String(),
      'monitoringStartTime': monitoringStartTime.toIso8601String(),
      'lastUsed': lastUsed.toIso8601String(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
    };
  }

  factory AppUsageModel.fromJson(Map<String, dynamic> json) {
    Uint8List? icon;
    if (json['iconBase64'] != null) {
      try {
        icon = base64Decode(json['iconBase64']);
      } catch (_) {
        icon = null;
      }
    }

    return AppUsageModel(
      packageName: json['packageName'],
      appName: json['appName'],
      iconBytes: icon,
      iconPath: json['iconPath'],
      dailyLimit: Duration(minutes: json['dailyLimit']),
      currentUsage: Duration(minutes: json['currentUsage']),
      isMonitored: json['isMonitored'],
      lastUsed: DateTime.parse(json['lastUsed']),
      sessions: (json['sessions'] as List?)
          ?.map((s) => UsageSession.fromJson(s))
          .toList() ?? [],
      notified30: json['notified30'] ?? false,
      notified60: json['notified60'] ?? false,
      notified90: json['notified90'] ?? false,
      isLocked: json['isLocked'] ?? false,
      overshotDuration: Duration(minutes: (json['overshotDuration'] ?? 0)),
      lockStartTime: json['lockStartTime'] != null ? DateTime.parse(json['lockStartTime']) : null,
      monitoringStartTime: json['monitoringStartTime'] != null ? DateTime.parse(json['monitoringStartTime']) : DateTime.now(),
    );
  }
}

class UsageSession {
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;

  UsageSession({
    required this.startTime,
    required this.endTime,
    required this.duration,
  });

  Map<String, dynamic> toJson() {
    return {
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'duration': duration.inMinutes,
    };
  }

  factory UsageSession.fromJson(Map<String, dynamic> json) {
    return UsageSession(
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      duration: Duration(minutes: json['duration']),
    );
  }
}

class DailyUsageStats {
  final DateTime date;
  final Map<String, Duration> appUsage;
  final Duration totalUsage;
  final int totalAppsUsed;

  DailyUsageStats({
    required this.date,
    required this.appUsage,
    required this.totalUsage,
    required this.totalAppsUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'appUsage': appUsage.map((key, value) => MapEntry(key, value.inMinutes)),
      'totalUsage': totalUsage.inMinutes,
      'totalAppsUsed': totalAppsUsed,
    };
  }

  factory DailyUsageStats.fromJson(Map<String, dynamic> json) {
    return DailyUsageStats(
      date: DateTime.parse(json['date']),
      appUsage: (json['appUsage'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, Duration(minutes: value))),
      totalUsage: Duration(minutes: json['totalUsage']),
      totalAppsUsed: json['totalAppsUsed'],
    );
  }
}

