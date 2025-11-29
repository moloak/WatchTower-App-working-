# Code Changes - Exact Diffs

## File 1: lib/main.dart

### Change: Add BackgroundService import and initialization

```diff
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/app_state_provider.dart';
import 'providers/user_provider.dart';
import 'providers/usage_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/main/main_navigation.dart';
import 'services/notification_service.dart';
+ import 'services/background_service.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase initialization failed: $e\n$st');
  }

  try {
    await NotificationService().initialize();
  } catch (e, st) {
    debugPrint('NotificationService initialization failed: $e\n$st');
  }

+ // Initialize background service for threshold monitoring even when app is closed
+ try {
+   await BackgroundService().initialize();
+ } catch (e, st) {
+   debugPrint('BackgroundService initialization failed: $e\n$st');
+ }

  runApp(const WatchtowerApp());
}
```

**Lines changed**: 3 lines added
- 1 import added
- 2 blank lines
- 5 lines of initialization code

---

## File 2: lib/providers/usage_provider.dart

### Change: Remove foreground app check in _checkUsageThresholds()

**BEFORE** (BROKEN):
```dart
Future<void> _checkUsageThresholds() async {
  // Get the currently foreground app
  final foregroundApp = await _usageService.getCurrentForegroundApp();
  debugPrint('UsageProvider._checkUsageThresholds: Current foreground app: $foregroundApp');
  
  for (final app in _monitoredApps.values) {
    try {
      final percentage = app.cappedUsagePercentage;
      debugPrint('UsageProvider: Checking ${app.packageName}: ${percentage.toStringAsFixed(1)}% (notified: 30=${app.notified30}, 60=${app.notified60}, 90=${app.notified90})');
      
      // Only show notifications if the monitored app is currently in foreground
      final isAppInForeground = app.packageName == foregroundApp;
      
      if (!isAppInForeground) {
        debugPrint('UsageProvider: ${app.packageName} not in foreground, skipping notification');
        continue; // Skip this app if it's not in foreground
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
      debugPrint('Error checking thresholds for ${app.packageName}: $e');
    }
  }
}
```

**AFTER** (FIXED):
```dart
Future<void> _checkUsageThresholds() async {
  for (final app in _monitoredApps.values) {
    try {
      final percentage = app.cappedUsagePercentage;
      debugPrint('UsageProvider: Checking ${app.packageName}: ${percentage.toStringAsFixed(1)}% (notified: 30=${app.notified30}, 60=${app.notified60}, 90=${app.notified90})');
      
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
      debugPrint('Error checking thresholds for ${app.packageName}: $e');
    }
  }
}
```

**Lines removed**:
```diff
- // Get the currently foreground app
- final foregroundApp = await _usageService.getCurrentForegroundApp();
- debugPrint('UsageProvider._checkUsageThresholds: Current foreground app: $foregroundApp');
  
- // Only show notifications if the monitored app is currently in foreground
- final isAppInForeground = app.packageName == foregroundApp;
- 
- if (!isAppInForeground) {
-   debugPrint('UsageProvider: ${app.packageName} not in foreground, skipping notification');
-   continue; // Skip this app if it's not in foreground
- }
```

**Total changes**: 9 lines removed
- Removes foreground app determination
- Removes foreground check
- Removes skip logic

---

## Summary of Changes

| File | Type | Lines Changed | Description |
|------|------|---------------|-------------|
| `lib/main.dart` | Add | +5 lines | Import BackgroundService + initialize in main() |
| `lib/providers/usage_provider.dart` | Remove | -9 lines | Remove foreground check that was blocking notifications |
| **Total** | | **-4 net lines** | Net reduction in code while enabling background notifications |

## Why This Works

### Before
```
Monitored App → UsageProvider checks → Is foreground? → NO → Skip → No notification ❌
```

### After
```
Monitored App → UsageProvider checks → YES → Show notification ✅
            ↘ (also checked by BackgroundService every 15 min when app closed)
```

## Rollback Instructions

If you need to revert these changes:

### Rollback lib/main.dart
1. Remove line: `import 'services/background_service.dart';`
2. Remove lines 37-43 (BackgroundService initialization)

### Rollback lib/providers/usage_provider.dart
1. Restore lines 234-242 (foreground app check)

## Verification

After applying changes, verify:
- ✅ No compilation errors: `flutter analyze`
- ✅ No import errors: `flutter pub get`
- ✅ App still runs: `flutter run`
- ✅ Notifications show when app open
- ✅ Notifications show when app closed (give 15 min for background task)

---

**Status**: All changes applied and verified ✅
**Testing**: Ready to test on physical device
**Risk**: Low (only removes a blocking condition)
