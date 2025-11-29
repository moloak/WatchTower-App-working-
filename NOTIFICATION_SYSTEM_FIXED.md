# Notification System - Fixed Implementation

## Problem Solved
The previous notification system only showed warnings when the app was in the foreground. Notifications are now shown even when:
- The app is closed/backgrounded
- Another app is in the foreground
- The device is locked

## Solution Overview

### 1. **Removed Foreground Check** 
`lib/providers/usage_provider.dart` - `_checkUsageThresholds()`
- ✅ Removed: `final isAppInForeground = app.packageName == foregroundApp;`
- ✅ Removed: `if (!isAppInForeground) continue;`
- Now checks ALL monitored apps regardless of foreground/background state

### 2. **Background Service Integration**
`lib/services/background_service.dart` - Handles notifications when app is closed
- Runs periodic threshold checks every **15 minutes** (configurable)
- Checks usage percentages against daily limits
- Shows notifications for: 30%, 60%, and 90% thresholds
- Uses `SharedPreferences` to track which notifications were already shown today

### 3. **Enabled Background Service in Main**
`lib/main.dart` - Now initializes the BackgroundService
```dart
// Initialize background service for threshold monitoring even when app is closed
try {
  await BackgroundService().initialize();
} catch (e, st) {
  debugPrint('BackgroundService initialization failed: $e\n$st');
}
```

### 4. **Heads-Up Notifications**
`lib/services/notification_service.dart` - Configured for maximum visibility
- `fullScreenIntent: true` - Shows notification above other apps
- `Importance.max` and `Priority.max` - Highest priority
- `enableVibration: true` - Device vibrates
- `enableLights: true` - LED lights up
- Works even when device is locked

## How It Works

### When App is in Foreground
1. `UsageProvider._monitorUsage()` runs every 2 seconds
2. Checks if any monitored app has reached thresholds (30%, 60%, 90%)
3. Shows notification via `NotificationService`
4. Marks app notification state (e.g., `notified30=true`)

### When App is Closed/Backgrounded
1. `BackgroundService` runs via Android Workmanager
2. Periodic task triggers every 15 minutes (`thresholdCheckTask`)
3. Reads usage data from `LocalUsageStorage`
4. Compares current usage to daily limits
5. Shows notification if threshold reached and not already shown today
6. Stores notification state in `SharedPreferences` with date key

### Notification Priority (Highest First)
1. **90% Threshold** - Final warning, app will be locked soon
2. **60% Threshold** - Middle warning  
3. **30% Threshold** - Initial warning

## Key Features

✅ **Real-time notifications** - When app is in foreground (every 2 seconds)
✅ **Background monitoring** - When app is closed (every 15 minutes)
✅ **Non-intrusive** - Only shows each threshold once per day
✅ **High visibility** - Heads-up notifications with vibration and lights
✅ **Works through locks** - Shows on locked screen via `fullScreenIntent`
✅ **Efficient** - Minimal battery drain, periodic checks only

## Configuration

To adjust notification frequency, edit `lib/services/background_service.dart`:

```dart
// Current: every 15 minutes
await wm.Workmanager().registerPeriodicTask(
  'threshold-check-unique-id',
  thresholdCheckTask,
  frequency: const Duration(minutes: 15),  // Change this
  initialDelay: const Duration(minutes: 1),
);
```

## Testing Notifications

### Foreground (App Open)
1. Open WatchTower app
2. Add a monitored app with short daily limit (e.g., 5 minutes)
3. Use the app to approach the limit
4. Watch for notifications at 30%, 60%, 90%

### Background (App Closed)
1. Close the WatchTower app
2. Use a monitored app to exceed 30% of daily limit
3. Wait up to 15 minutes for background task to run
4. Notification should appear even with app closed

### Android DevTools (For Testing)
```bash
adb shell dumpsys notification
adb shell cmd notification allow_listener com.example.watchtower/.NotificationListener
```

## Android Permissions Required
In `android/app/src/main/AndroidManifest.xml`:
- ✅ `INTERNET`
- ✅ `RECEIVE_BOOT_COMPLETED` (for Workmanager)
- ✅ `SCHEDULE_EXACT_ALARM` (for precise scheduling)
- ✅ `POST_NOTIFICATIONS` (for notifications on Android 13+)

## Debugging

Enable debug logs to see notification flow:
```bash
flutter run -v  # Verbose logging
# Look for these debug messages:
# [BackgroundService] Running app monitoring
# [BackgroundService] Checking usage thresholds...
# [BackgroundService] Notified [AppName] at XX% threshold
# UsageProvider: XX% threshold reached
```

## Architecture Diagram

```
┌─────────────────────────────────────────┐
│     WatchTower App (Running)            │
│  ┌──────────────────────────────────┐   │
│  │ UsageProvider._monitorUsage()    │   │
│  │ (checks every 2 seconds)         │   │
│  └──────────────────────────────────┘   │
│           ↓                               │
│  ┌──────────────────────────────────┐   │
│  │ NotificationService              │   │
│  │ .showUsageWarningNotification()   │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
           ↓
    ┌──────────────────┐
    │ Heads-up Alert   │
    │ (Vibration, LED) │
    └──────────────────┘

┌─────────────────────────────────────────┐
│   Android System (App Closed)           │
│  ┌──────────────────────────────────┐   │
│  │ Workmanager                      │   │
│  │ (periodic task every 15 min)     │   │
│  └──────────────────────────────────┘   │
│           ↓                               │
│  ┌──────────────────────────────────┐   │
│  │ BackgroundService                │   │
│  │ ._handleThresholdCheck()          │   │
│  └──────────────────────────────────┘   │
│           ↓                               │
│  ┌──────────────────────────────────┐   │
│  │ NotificationService              │   │
│  │ .showUsageWarningNotification()   │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
           ↓
    ┌──────────────────┐
    │ System Alert     │
    │ (Even on lock)   │
    └──────────────────┘
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Notifications not showing | Check notification permission in phone settings |
| Only showing in foreground | Verify BackgroundService.initialize() is called |
| Too many notifications | Increase frequency in registerPeriodicTask() |
| Notifications delayed | Normal for background tasks (up to 15 min delay) |
| App crashes on background | Check that Firebase is initialized before background task |

## Next Steps

1. **Test thoroughly** on multiple Android versions (8, 10, 12, 13+)
2. **Monitor battery impact** using Android DevTools
3. **Adjust frequency** if too many or too few notifications
4. **Add user preferences** for notification timing if needed
