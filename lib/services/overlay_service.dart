import 'package:flutter/foundation.dart';
import '../models/app_usage_model.dart';

/// OverlayService has been deprecated. All overlays have been removed.
/// Users now only receive notification-based usage warnings.
/// This service is kept for backwards compatibility but all methods are no-ops.
class OverlayService {
  static final OverlayService _instance = OverlayService._internal();
  factory OverlayService() => _instance;
  OverlayService._internal();

  /// No-op: Overlays have been removed. Use notifications instead.
  Future<void> showUsageWarning(AppUsageModel app, WarningLevel level) async {
    debugPrint('OverlayService.showUsageWarning is deprecated. Use NotificationService instead.');
  }

  /// No-op: No overlays to hide.
  Future<void> hideOverlay() async {
    debugPrint('OverlayService.hideOverlay is deprecated and does nothing.');
  }

  /// No-op: Overlay permissions no longer needed.
  Future<bool> hasOverlayPermission() async {
    return true; // Return true so callers don't break
  }

  /// No-op: Overlay permissions no longer needed.
  Future<bool> requestOverlayPermission() async {
    return true; // Return true so callers don't break
  }

  /// No-op: Cleanup.
  void dispose() {
    debugPrint('OverlayService disposed.');
  }
}

enum WarningLevel {
  thirtyPercent,
  sixtyPercent,
  ninetyPercent,
}

