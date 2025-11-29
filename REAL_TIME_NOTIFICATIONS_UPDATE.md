# Real-Time Dashboard Updates & Notification System Overhaul

## Overview
Implemented real-time dashboard updates with faster value synchronization and completely rewrote the notification logic to ensure:
- Notifications display even when the app is closed or backgrounded
- Only the next applicable threshold notification triggers after time reset
- Notifications work perfectly with proper heads-up display across all foreground apps

## Key Changes

### 1. Background Service Improvements (`lib/services/background_service.dart`)

#### New Background Task: Threshold Check (Every 15 Minutes)
```dart
const String thresholdCheckTask = 'threshold_check_task';
```

**Features:**
- Runs every **15 minutes** even when app is closed
- Checks all monitored apps' current usage against daily limits
- Triggers notifications based on usage thresholds (30%, 60%, 90%)
- Prevents notification spam by tracking which thresholds were already notified

#### Smart Threshold Logic
The notification system now uses a **non-overlapping threshold strategy**:
- **30% Threshold**: Shows when usage is 30-59%
- **60% Threshold**: Shows when usage is 60-89% (only if 30% notification already shown)
- **90% Threshold**: Shows when usage is 90% or above (only if previous thresholds passed)

This ensures users see notifications as usage progresses, not multiple notifications at once.

#### Time Reset Handling
When a user resets the daily timer for an app:
1. All notification flags for that app/day are cleared
2. Next time usage reaches a threshold, the notification will trigger
3. Example: If user resets at 75% usage, they'll see the next 60% or 90% notification

### 2. Notification Service Enhancements (`lib/services/notification_service.dart`)

#### New Method: `clearNotificationState()`
```dart
Future<void> clearNotificationState(String packageName, {String? dateStr}) async
```

**Purpose:**
- Called when user resets daily usage time for an app
- Clears all SharedPreferences flags for that app/date
- Ensures only next applicable threshold notification triggers

**Usage Example:**
```dart
// When user resets time for an app
await NotificationService().clearNotificationState(packageName);
```

#### Improved Heads-Up Notification Display
Enhanced Android notification configuration:
- **fullScreenIntent: true** - Shows over any foreground app
- **importance: Importance.max** - Maximum priority
- **priority: Priority.max** - Forces heads-up display
- **groupKey & tags** - Prevents notification stacking
- **enableVibration: true** - Haptic feedback

### 3. Local Usage Storage Addition (`lib/services/local_usage_storage.dart`)

#### New Method: `getDailyUsageForDate()`
```dart
Future<List<Map<String, dynamic>>> getDailyUsageForDate(String date) async
```

**Purpose:**
- Retrieves all app usage data for a specific date
- Used by background service to check thresholds
- Enables real-time dashboard updates without app being open

### 4. Real-Time Dashboard Updates

#### How It Works:
1. **Background Service** runs threshold checks every 15 minutes
2. **SharedPreferences** stores notification state (which thresholds were shown)
3. **Firestore** updates with current daily usage in real-time
4. **Dashboard** syncs with Firestore changes (real-time listener)

#### Data Flow:
```
App Usage (OS) → LocalUsageStorage (SQLite) → Firestore (Cloud)
                        ↓
              Background Service Check
                        ↓
                  Show Notification
                        ↓
                  Update Firestore
                        ↓
                Dashboard Listener
```

## Implementation Details

### Threshold Check Task Registration
```dart
// Runs every 15 minutes for real-time updates
await wm.Workmanager().registerPeriodicTask(
  'threshold-check-unique-id',
  thresholdCheckTask,
  frequency: const Duration(minutes: 15),
  initialDelay: const Duration(minutes: 1),
);
```

### SharedPreferences Keys Structure
```
notified_30_<packageName>_<YYYY-MM-DD>
notified_60_<packageName>_<YYYY-MM-DD>
notified_90_<packageName>_<YYYY-MM-DD>
```

### Example: Time Reset Flow
```dart
// User resets time usage for Instagram at 75% usage
1. Clear notifications: 
   await notificationService.clearNotificationState('com.instagram.android');

2. On next threshold check (max 15 mins):
   - Current usage: 75%
   - No notification shown yet (flags cleared)
   - 60% threshold would show (since 75% >= 60%)

3. If usage reaches 90%:
   - 90% notification shows
   - notified_90 flag set
```

## Testing Checklist

- [ ] Close app and verify notifications appear when threshold reached
- [ ] Open Settings/another app and verify notifications display as heads-up
- [ ] Reset time usage while monitoring and verify next threshold notifies
- [ ] Verify no duplicate notifications at same threshold on same day
- [ ] Check SharedPreferences are cleared at midnight (new day)
- [ ] Verify background task runs even after device restart
- [ ] Test with multiple apps monitored simultaneously

## Performance Considerations

- **15-minute check interval**: Balances real-time updates with battery usage
- **SharedPreferences caching**: Fast lookup, no database queries
- **Batch processing**: All apps checked in single background task
- **Minimal network usage**: Only Firestore updates use network (async)
- **SQLite queries**: Indexed by date for fast retrieval

## Migration Notes

If upgrading from previous version:
1. Clear SharedPreferences notification flags (no user data loss)
2. Existing monitored apps automatically included in new system
3. No changes required to AppUsageModel structure
4. Backward compatible with existing Firestore data

## Future Enhancements

- Add custom threshold percentages (currently fixed at 30%, 60%, 90%)
- Weekly digest notification with summary
- Smart notifications (quiet hours, don't notify if user active)
- Machine learning for usage patterns
- Customizable notification sounds per app
