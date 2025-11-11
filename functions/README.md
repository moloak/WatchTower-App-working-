# Weekly Summary Cloud Function

This folder contains a simple Firebase Cloud Function that accepts a weekly
summary POSTed from devices. The function expects:

- Authorization: Bearer <Firebase ID Token>
- JSON body: { weekStart: 'YYYY-MM-DD', generatedAt: ISOString, apps: { packageName: totalMinutes, ... } }

The function verifies the ID token with the Firebase Admin SDK and writes the
summary under `users/<uid>/weekly_summaries/<weekStart>` in Firestore.

To deploy:

1. Install dependencies:

   cd functions
   npm install

2. Deploy with the Firebase CLI:

   firebase deploy --only functions:pushWeeklySummary

Make sure your Firebase project is selected and you've logged into the CLI.

Scheduled aggregation options
-----------------------------
If you do NOT want to upgrade your Firebase project to Blaze (pay-as-you-go),
you have two viable options that do not require scheduled Cloud Functions:

1) Device-driven pushes only (recommended for free tier)
    - Deploy only the HTTP function `pushWeeklySummary` (no scheduler needed).
    - The app's background worker (Workmanager) will run on the device and POST
       the weekly summary to the HTTP endpoint when due. This requires no Blaze
       plan. It relies on the device being able to run the background job (Android).

    To deploy only the HTTP endpoint (free plan):

       cd functions
       npm install
       firebase deploy --only functions:pushWeeklySummary

2) Server aggregation (requires Blaze)
    - Deploy `aggregateWeeklySummaries` (scheduled function) which runs weekly
       in Cloud Functions and aggregates per-day docs already written to
       `users/<uid>/daily_usage/<YYYY-MM-DD>`.

    To deploy both (Blaze required for the scheduler):

       cd functions
       npm install
       firebase deploy --only functions:pushWeeklySummary,functions:aggregateWeeklySummaries

Notes
-----
- The client already writes per-day docs to Firestore and will also attempt
   to POST the weekly summary to `pushWeeklySummary` when available.
- If you prefer not to enable Blaze, use option (1) above and do not deploy
   `aggregateWeeklySummaries`. The device-side Workmanager will attempt pushes
   daily and call the HTTP endpoint when the week is complete.
- For QA you can still use the admin trigger `triggerAggregateWeeklySummaries`
   (HTTP admin endpoint) but keep it protected with an admin secret and avoid
   deploying it publicly in production.

Password reset helper
---------------------

This project now also includes an HTTP function `createPasswordResetLink` that
provides a secure server-side endpoint for the Flutter app to request a
password reset flow. It uses the Firebase Admin SDK to prevent user
enumeration and to generate a password reset link. Optionally it can send the
email via SMTP if SMTP config is provided in functions config.

Usage:

1. Set environment/config variables (example):

   firebase functions:config:set smtp.host="smtp.example.com" smtp.port="587" smtp.user="noreply@example.com" smtp.pass="smtppassword" smtp.from="Watchtower <noreply@example.com>" password_reset.continue_url="https://your-app.example.com/reset" expose.reset_link="false"

2. Deploy the function:

   firebase deploy --only functions:createPasswordResetLink

3. Update the Flutter client `lib/services/auth_backend.dart` and set
   `kAuthBackendEndpoint` to the deployed function URL.

Security notes
--------------
- The function purposely avoids revealing whether an email exists. If the
  email does not exist the function returns a neutral response. This avoids
  user enumeration attacks.
- Do not enable `expose.reset_link` in production — it is only for testing.

Testing the schedule immediately
-------------------------------
If you want to test aggregation right away without waiting for the scheduler,
deploy the `triggerAggregateWeeklySummaries` function and call it with the
admin secret.

1. Set a secure secret for testing. Locally you can set an environment variable
   before deployment, or set Functions config:

   firebase functions:config:set admin.secret="my-test-secret"

2. Deploy the trigger function:

   firebase deploy --only functions:triggerAggregateWeeklySummaries

3. Call the function (replace URL from deploy output):

   curl -X POST "https://<REGION>-<PROJECT>.cloudfunctions.net/triggerAggregateWeeklySummaries" -H "x-admin-secret: my-test-secret"

If successful, the function will return { success: true, weekStart: "YYYY-MM-DD" }
and you can inspect Firestore to confirm weekly summaries were written.

Remove or rotate the admin secret after testing to keep your endpoint secure.
