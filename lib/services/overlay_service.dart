import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../models/app_usage_model.dart';
import 'package:flutter/services.dart';

class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  static const MethodChannel _platform = MethodChannel('com.example.project_1/overlay');

  /// Initialize platform callbacks to receive overlay events from Android.
  void _initPlatformHandler() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'overlayHidden') {
  // Android overlay reported it was manually dismissed by the user
  debugPrint('[OverlayService] Platform callback received: overlayHidden ${call.arguments}');
        final pkg = call.arguments?['packageName'] as String?;
        _overlayController.add(OverlayEvent(
          type: OverlayEventType.overlayHidden,
          app: null,
          packageName: pkg,
          message: call.arguments?['message'] ?? 'Overlay hidden',
        ));
      }
    });
    // start the fallback poller so we can detect overlay dismisses saved by native code
    _startFallbackPoller();
  }


  bool _isOverlayActive = false;
  Timer? _countdownTimer;
  final StreamController<OverlayEvent> _overlayController = 
      StreamController<OverlayEvent>.broadcast();

  Stream<OverlayEvent> get overlayStream => _overlayController.stream;
  bool get isOverlayActive => _isOverlayActive;

  bool _platformHandlerInitialized = false;

  Future<bool> requestOverlayPermission() async {
    try {
      final status = await Permission.systemAlertWindow.request();
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
      return false;
    }
  }

  Future<bool> hasOverlayPermission() async {
    try {
      return await Permission.systemAlertWindow.isGranted;
    } catch (e) {
      debugPrint('Error checking overlay permission: $e');
      return false;
    }
  }

  Future<void> showUsageWarning(AppUsageModel app, WarningLevel level) async {
    if (!await hasOverlayPermission()) {
      debugPrint('Overlay permission not granted');
      return;
    }

    try {
      final message = _getWarningMessage(app, level);
      final title = _getWarningTitle(level);

      if (!_platformHandlerInitialized) {
        _initPlatformHandler();
        _platformHandlerInitialized = true;
      }

      // Ask platform to show overlay
      try {
        debugPrint('[OverlayService] Invoking platform showWarning for ${app.packageName}');
        await _platform.invokeMethod('showWarning', {
          'title': title,
          'message': message,
          'packageName': app.packageName,
        });
      } catch (e) {
        debugPrint('[OverlayService] showWarning platform invoke failed: $e');
        // platform may not be available on non-Android platforms
      }

      // TODO: Implement overlay functionality
      debugPrint('Overlay Warning: $title - $message');

      _overlayController.add(OverlayEvent(
        type: OverlayEventType.warning,
        app: app,
        level: level,
        message: message,
      ));

      // Auto-hide warning after 5 seconds
      Timer(const Duration(seconds: 5), () {
        hideOverlay();
      });

    } catch (e) {
      debugPrint('Error showing usage warning: $e');
    }
  }

  Future<void> showAppLockOverlay(AppUsageModel app) async {
    if (!await hasOverlayPermission()) {
      debugPrint('Overlay permission not granted');
      return;
    }

    try {
      _isOverlayActive = true;

      if (!_platformHandlerInitialized) {
        _initPlatformHandler();
        _platformHandlerInitialized = true;
      }

      try {
        debugPrint('[OverlayService] Invoking platform showLock for ${app.packageName}');
        await _platform.invokeMethod('showLock', {
          'title': 'App Locked',
          'message': 'App locked until tomorrow.\nTake a break and come back fresh tomorrow.',
          'packageName': app.packageName,
        });
      } catch (e) {
        debugPrint('[OverlayService] showLock platform invoke failed: $e');
      }

      // TODO: Implement overlay functionality
      debugPrint('App Lock Overlay: App locked until tomorrow');

      _overlayController.add(OverlayEvent(
        type: OverlayEventType.appLock,
        app: app,
        message: 'App locked until tomorrow',
      ));

    } catch (e) {
      debugPrint('Error showing app lock overlay: $e');
    }
  }

  // (removed deprecated internal helper _startCountdown)

  /// Start a countdown for the provided duration. When the countdown
  /// completes the app will be locked (showAppLockOverlay will be invoked).
  void startCountdown(Duration duration, AppUsageModel app) {
    _countdownTimer?.cancel();
    // If duration is zero or negative, lock immediately
    if (duration <= Duration.zero) {
      _overlayController.add(OverlayEvent(
        type: OverlayEventType.countdownComplete,
        app: app,
        message: 'Countdown completed',
      ));
      showAppLockOverlay(app);
      return;
    }

    _countdownTimer = Timer(duration, () {
      _overlayController.add(OverlayEvent(
        type: OverlayEventType.countdownComplete,
        app: app,
        message: 'Countdown completed',
      ));
      showAppLockOverlay(app);
    });
  }

  Future<void> hideOverlay() async {
    try {
      // Ask platform to hide overlay if available
      try {
        debugPrint('[OverlayService] Invoking platform hideOverlay');
        await _platform.invokeMethod('hideOverlay');
      } catch (_) {}
      debugPrint('Hiding overlay');
      // If overlay was active and is being hidden, emit an overlayHidden
      // event so callers can measure overshot time.
      if (_isOverlayActive) {
        _overlayController.add(OverlayEvent(
          type: OverlayEventType.overlayHidden,
          app: null,
          message: 'Overlay manually hidden by user',
        ));
      }

      _isOverlayActive = false;
      _countdownTimer?.cancel();
    } catch (e) {
      debugPrint('Error hiding overlay: $e');
    }
  }

  // Poll for fallback overlay dismisses recorded in Android SharedPreferences.
  Timer? _fallbackPoller;
  bool _fallbackPollerStarted = false;

  void _startFallbackPoller() {
    if (_fallbackPollerStarted) return;
    _fallbackPollerStarted = true;
    // Poll every 2 seconds for any saved overlay dismiss records
    _fallbackPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final res = await _platform.invokeMethod('consumeOverlayDismiss');
        if (res != null) {
          debugPrint('[OverlayService] consumeOverlayDismiss returned: $res');
          String? pkg;
          try {
            if (res is Map) {
              pkg = res['packageName'] as String?;
            }
          } catch (_) {
            pkg = null;
          }
          _overlayController.add(OverlayEvent(
            type: OverlayEventType.overlayHidden,
            app: null,
            packageName: pkg,
            message: 'Overlay dismissed (fallback)',
          ));
        }
      } catch (e) {
        // ignore cross-platform errors
      }
    });
  }

  String _getWarningMessage(AppUsageModel app, WarningLevel level) {
    final remainingTime = app.remainingTime;
    final hours = remainingTime.inHours;
    final minutes = remainingTime.inMinutes % 60;

    switch (level) {
      case WarningLevel.thirtyPercent:
        return 'You\'ve used 30% of your daily limit for ${app.appName}.\n\nTime remaining: ${hours}h ${minutes}m';
      case WarningLevel.sixtyPercent:
        return 'You\'ve used 60% of your daily limit for ${app.appName}.\n\nTime remaining: ${hours}h ${minutes}m';
      case WarningLevel.ninetyPercent:
        return 'You\'ve used 90% of your daily limit for ${app.appName}.\n\nThis is your last warning! Please save your work.\n\nTime remaining: ${hours}h ${minutes}m';
    }
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

  void dispose() {
    _countdownTimer?.cancel();
    _overlayController.close();
    // Cancel fallback poller if started
    _fallbackPoller?.cancel();
  }
}

enum WarningLevel {
  thirtyPercent,
  sixtyPercent,
  ninetyPercent,
}

class OverlayEvent {
  final OverlayEventType type;
  final AppUsageModel? app;
  final String? packageName;
  final WarningLevel? level;
  final String message;
  final DateTime timestamp;

  OverlayEvent({
    required this.type,
    this.app,
    this.packageName,
    this.level,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum OverlayEventType {
  warning,
  appLock,
  countdownComplete,
  overlayHidden,
}
