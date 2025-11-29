# Notification System Fix - Verification Checklist

## Changes Made ✅

### 1. UsageProvider (`lib/providers/usage_provider.dart`)
- [x] Removed foreground app check
- [x] Now monitors ALL apps regardless of state
- [x] Thresholds checked: 30%, 60%, 90%

### 2. Main App (`lib/main.dart`)
- [x] Added BackgroundService import
- [x] Added BackgroundService initialization in main()
- [x] Wrapped in try-catch for safety

### 3. Existing Components (No changes needed)
- [x] BackgroundService - Already implemented
- [x] NotificationService - Already configured with fullScreenIntent
- [x] LocalUsageStorage - Already supports background reading
- [x] SharedPreferences - Used for tracking notifications

## How to Test

### Test 1: Foreground Notifications (App Open)
1. Open WatchTower app
2. Add a monitored app
3. Set a very short daily limit (e.g., 1-5 minutes)
4. Use that app actively
5. Watch for notifications at 30%, 60%, 90%
6. **Expected**: Notifications appear within 2-4 seconds of threshold

### Test 2: Background Notifications (App Closed)
1. Close WatchTower app completely
2. Use a monitored app to reach 30%+ of daily limit
3. Wait up to 15 minutes
4. **Expected**: Notification shows even with app closed

### Test 3: Lock Screen Notifications
1. Lock your device
2. Have a monitored app near threshold
3. Let the threshold trigger (background task)
4. **Expected**: Notification visible on lock screen with vibration

### Test 4: Notification Deduplication
1. Let a notification trigger
2. Check logs for "notified_30_[packageName]_[date]" in SharedPreferences
3. Wait until next threshold
4. **Expected**: Only one notification per threshold per day

## Debug Commands

```bash
# View all notifications on device
adb shell dumpsys notification | grep -A 10 "watchtower"

# View Workmanager tasks
adb shell dumpsys jobscheduler | grep -A 5 "workmanager"

# View SharedPreferences
adb shell run-as com.example.watchtower cat shared_prefs/FlutterSharedPreferences.xml

# Get verbose logs
flutter run -v 2>&1 | grep -E "(BackgroundService|UsageProvider|Notification)"
```

## Files Modified
- ✅ `lib/main.dart` - Added BackgroundService initialization
- ✅ `lib/providers/usage_provider.dart` - Removed foreground check
- ✅ `NOTIFICATION_SYSTEM_FIXED.md` - Documentation (NEW)
- ✅ `NOTIFICATION_SYSTEM_FIX_CHECKLIST.md` - This file (NEW)

## Files That Should NOT Change
- ✅ `lib/services/background_service.dart` - Already correct
- ✅ `lib/services/notification_service.dart` - Already configured
- ✅ `lib/services/local_usage_storage.dart` - Working fine
- ✅ `android/app/src/main/AndroidManifest.xml` - Permissions already set

## Expected Behavior After Fix

### Scenario 1: User monitors YouTube with 10 min/day limit
- 10:00 AM - User starts YouTube
- 10:00:30 AM - App running in foreground, UsageProvider checks every 2s
- 10:01:00 AM - YouTube reaches 3 minutes (30% of 10 min limit)
  - ✅ Notification 1: "YouTube - 30% of daily limit reached"
- 10:05:00 AM - YouTube reaches 6 minutes (60% of limit)
  - ✅ Notification 2: "YouTube - 60% of daily limit reached"
- User closes WatchTower app
- 10:08:00 AM - YouTube reaches 9 minutes (90% of limit)
  - ✅ Notification 3: "YouTube - 90% of daily limit reached" (from BackgroundService)
- 10:10:00 AM - YouTube reaches 10+ minutes
  - ✅ App is locked (no more notifications today)

### Scenario 2: Background monitoring
- 7:00 PM - User closes WatchTower app
- 7:05 PM - Uses Instagram, reaches 45% of daily limit
- 7:15 PM - BackgroundService wakes up, checks thresholds
- 7:15:05 PM - Finds Instagram at 45%, shows 30% notification
  - ✅ Notification appears even though app is closed
- Next day, same process repeats with fresh notification flags

## Potential Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Notifications not showing | Permission denied | Grant notification permission in settings |
| Only in foreground | BackgroundService didn't initialize | Check main.dart logs |
| Duplicates | SharedPreferences not working | Check storage permission |
| Delayed (>15 min) | Normal system behavior | Expected for background tasks |
| App crashes | Firebase not initialized | Check try-catch in main.dart |

## Next: Performance Optimization (Optional)

If battery drain is high, consider:
1. Increasing background check frequency from 15 to 30 minutes
2. Using exact alarms only for 90% threshold
3. Disabling background checks if phone is in low battery mode

## Final Checklist Before Release

- [ ] Test on Android 8
- [ ] Test on Android 10
- [ ] Test on Android 12
- [ ] Test on Android 13
- [ ] Test with device locked
- [ ] Test with another app in foreground
- [ ] Check battery consumption (adb shell dumpsys batteryproperties)
- [ ] Verify no crashes in logcat
- [ ] Run flutter analyze (no errors)
- [ ] Test notification deduplication (only 1 per threshold per day)
