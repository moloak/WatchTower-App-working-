# Integration Guide: Time Reset with Notification Clearing

## Overview
This guide shows how to integrate the new notification clearing system when users reset their daily app usage time.

## Integration Points

### 1. In AppUsageService (When User Resets Daily Limit)

If you have a method to reset daily usage for an app, add notification clearing:

```dart
// lib/services/app_usage_service.dart

Future<void> resetDailyUsageForApp(String packageName) async {
  try {
    // Your existing reset logic
    if (_monitoredApps.containsKey(packageName)) {
      final app = _monitoredApps[packageName]!;
      
      // Reset the app's current usage to zero
      final resetApp = app.copyWith(
        currentUsage: Duration.zero,
        notified30: false,
        notified60: false,
        notified90: false,
        // ... other reset logic
      );
      
      _monitoredApps[packageName] = resetApp;
      
      // **NEW: Clear notification state for this app**
      await NotificationService().clearNotificationState(packageName);
      
      // Broadcast the change
      _usageController.add(_monitoredApps);
      
      debugPrint('[AppUsageService] Reset daily usage for $packageName and cleared notifications');
    }
  } catch (e) {
    debugPrint('Error resetting daily usage: $e');
  }
}
```

### 2. In Dashboard/Apps Screen (Reset Button Handler)

When user taps "Reset" button:

```dart
// lib/screens/main/apps_screen.dart (or dashboard_screen.dart)

Future<void> _handleResetDailyLimit(AppUsageModel app) async {
  try {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Daily Limit'),
        content: Text(
          'Reset daily usage timer for ${app.appName}? '
          'You will receive notifications again when reaching threshold.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Reset in app usage service
    await _appUsageService.resetDailyUsageForApp(app.packageName);
    
    // **NEW: Clear notification state**
    await NotificationService().clearNotificationState(app.packageName);
    
    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${app.appName} daily limit reset. You\'ll be notified again at 30% usage.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    debugPrint('Error resetting daily limit: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
```

### 3. In Provider (UserProvider)

If you manage app settings in Provider:

```dart
// lib/providers/app_usage_provider.dart (or equivalent)

Future<void> resetAppDailyUsage(String packageName) async {
  try {
    // Reset app usage
    final app = _monitoredApps[packageName];
    if (app != null) {
      final resetApp = app.copyWith(
        currentUsage: Duration.zero,
        notified30: false,
        notified60: false,
        notified90: false,
      );
      
      _monitoredApps[packageName] = resetApp;
      
      // **NEW: Clear notification flags for this app**
      await NotificationService().clearNotificationState(packageName);
      
      // Persist changes
      await _saveMonitoredApps();
      notifyListeners();
      
      debugPrint('[AppUsageProvider] Reset $packageName and cleared notifications');
    }
  } catch (e) {
    debugPrint('Error in resetAppDailyUsage: $e');
    rethrow;
  }
}
```

## UI Implementation Examples

### Example 1: Reset Button in App Details Card

```dart
Container(
  child: Row(
    children: [
      Expanded(
        child: ElevatedButton(
          onPressed: () => _handleResetDailyLimit(app),
          child: const Text('Reset Timer'),
        ),
      ),
    ],
  ),
)
```

### Example 2: Reset in Settings/Context Menu

```dart
PopupMenuItem(
  child: const Text('Reset Daily Limit'),
  onTap: () => _handleResetDailyLimit(app),
)
```

### Example 3: Swipe to Reset

```dart
Dismissible(
  key: Key(app.packageName),
  direction: DismissDirection.startToEnd,
  onDismissed: (_) => _handleResetDailyLimit(app),
  background: Container(
    color: Colors.green,
    child: const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('Reset', style: TextStyle(color: Colors.white)),
      ),
    ),
  ),
  child: AppUsageListTile(app: app),
)
```

## Data Flow When User Resets Time

```
User Taps "Reset Button"
           ↓
Show Confirmation Dialog
           ↓
User Confirms
           ↓
Reset currentUsage to 0 ← AppUsageModel
           ↓
Set notification flags to false
           ↓
clearNotificationState() ← NotificationService
           ↓
Remove all SharedPreferences entries:
  - notified_30_<package>_<date>
  - notified_60_<package>_<date>
  - notified_90_<package>_<date>
           ↓
Broadcast changes via Provider/Stream
           ↓
Dashboard updates UI
           ↓
User sees "Usage: 0h 0m" 
and "Next notification at 30%"
           ↓
Background task runs (15 mins max)
           ↓
Checks usage → 0% (no notification)
```

## Important Notes

### Timing
- The background service runs every 15 minutes
- Maximum delay for next notification: 15 minutes after reset
- To trigger immediately: Kill app and restart (forces background check)

### Persistence
- Notification state is stored in SharedPreferences
- Will survive app restarts
- Automatically cleared at midnight (new day)

### User Communication
- Inform users that resetting clears notification history
- Explain they'll see notifications again when threshold is reached
- Example message: *"Reset complete! You'll receive notifications again at 30%, 60%, and 90% usage."*

### Edge Cases

**Case 1: User resets at 75% usage**
- Cleared flags: notified_60, notified_90
- Result: Next check will show 60% OR 90% notification (depending on current usage)

**Case 2: User resets multiple times in same day**
- Each reset clears that day's notification flags
- No accumulation of notifications
- Works as expected

**Case 3: User resets at 11:59 PM**
- Flags are cleared
- At midnight, new date starts
- Flags naturally reset (new date key)
- No conflicts

## Testing

```dart
// Test code to verify reset functionality
Future<void> testResetNotificationClearing() async {
  const packageName = 'com.instagram.android';
  final notificationService = NotificationService();
  
  // Simulate reaching 60% threshold
  final prefs = await SharedPreferences.getInstance();
  final today = DateTime.now().toString().split(' ')[0];
  await prefs.setBool('notified_60_${packageName}_$today', true);
  
  // Verify flag is set
  assert(prefs.getBool('notified_60_${packageName}_$today') ?? false);
  
  // Clear notifications (simulate user reset)
  await notificationService.clearNotificationState(packageName);
  
  // Verify flags are cleared
  assert(!(prefs.getBool('notified_60_${packageName}_$today') ?? false));
  
  debugPrint('✓ Reset notification clearing test passed');
}
```

## See Also
- `REAL_TIME_NOTIFICATIONS_UPDATE.md` - Complete system documentation
- `lib/services/notification_service.dart` - NotificationService implementation
- `lib/services/background_service.dart` - Background task implementation
