# Firebase Security Rules Fix for Sign-In

## Problem
Sign-in and sign-up are failing with **PERMISSION_DENIED** errors because Firestore security rules are not properly configured. When users authenticate, the app tries to read/write their user document but the rules deny access.

## Solution

### Step 1: Update Firestore Security Rules in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **watchtower-dev-8c0f7**
3. Navigate to **Firestore Database** → **Rules**
4. Replace ALL existing rules with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can read/write their own user document
    match /users/{userId} {
      allow read: if request.auth.uid == userId;
      allow write: if request.auth.uid == userId;
    }

    // Chat sessions: users can read/write their own sessions
    match /chatSessions/{document=**} {
      allow read, write: if request.auth.uid == resource.data.userId;
      allow create: if request.auth.uid != null;
    }

    // Agents collection - read-only for all authenticated users
    match /agents/{document=**} {
      allow read: if request.auth.uid != null;
      allow write: if false;
    }

    // Default deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

5. Click **Publish** button

### Step 2: Code Changes (Already Applied)

The app code has been updated to:
- Add `userId` field to all Firestore user documents for security rule validation
- Properly handle errors when reading user documents
- Rethrow errors so they're visible in debugging

## Testing the Fix

1. **Build and run the app:**
   ```
   flutter pub get
   flutter run
   ```

2. **Try to sign up:**
   - Email: test@example.com (use a real email)
   - Password: TestPassword123!
   - Name: Test User
   - You should receive a verification email

3. **Try to sign in with Google:**
   - Click "Sign in with Google"
   - Select your Google account
   - You should be logged in successfully

4. **Check for errors:**
   - Monitor the Flutter console for any "PERMISSION_DENIED" errors
   - If you see them, verify the Firestore rules were saved correctly

## Troubleshooting

**If still getting PERMISSION_DENIED:**
- ✓ Verify the Firestore rules are published (not in draft mode)
- ✓ Check the project ID is correct (watchtower-dev-8c0f7)
- ✓ Wait 1-2 minutes for rules to propagate
- ✓ Restart the app completely

**If sign-in still fails:**
- Check console logs for the specific error message
- Verify Firebase Authentication is enabled
- Ensure Google Sign-In credentials are configured in Firebase
- Check if the device has network connectivity to Google services

## Reference
- [Firestore Security Rules Documentation](https://firebase.google.com/docs/firestore/security/start)
- [Firebase Authentication Setup](https://firebase.google.com/docs/auth/flutter/start)
