import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../../services/auth_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSending = true);

    try {
      final email = _emailController.text.trim();
      // Prefer server-side validation to determine provider and create/send
      // the password reset link. This avoids email-enumeration risks and
      // avoids the deprecated fetchSignInMethodsForEmail client API.
      try {
        final resp = await requestPasswordReset(email);
        final canReset = resp['canReset'] as bool? ?? true;
        if (!canReset) {
          final reason = resp['reason'] as String? ?? 'provider';
          if (reason == 'google') {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in with your Google account')));
            return;
          }
          // Unknown provider block
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot reset password for this account')));
          return;
        }

        // If the server already sent the email, we can show the confirmation UI
        if (resp['sent'] == true) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('password_reset_in_progress', true);
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Password reset sent'),
              content: Text('A password reset email has been sent to $email. Open the email and click the link to reset your password. When you return to the app it will prompt you and then take you to the sign in page.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          if (mounted) Navigator.of(context).pop();
          return;
        }

        // Otherwise the server returned canReset=true but didn't send the email.
        // If the server returned a resetLink we could show it or open it. But
        // to preserve compatibility we will fallthrough to client-side send.
      } catch (e) {
        // If the backend call fails, fallback to client-side behavior below.
        debugPrint('Auth backend call failed: $e');
      }
      // Attempt to send password reset with ActionCodeSettings so that the
      // email link can be configured to open the app via Dynamic Links.
      // IMPORTANT: Replace 'https://watchtower.page.link/reset' and package/bundle
      // identifiers with your project's configured dynamic link domain and app ids.
      try {
        // IMPORTANT: Use a custom HTTPS URL that you control and configure
        // App Links (Android) and Universal Links (iOS) for that domain so
        // the link opens your app directly. Replace the placeholder below
        // with your app's configured domain (for example
        // 'https://auth.yourdomain.com/reset'). Do NOT keep the Firebase
        // Dynamic Links domain since that service is deprecated.
        final actionSettings = fb_auth.ActionCodeSettings(
          url: 'https://your-app.example.com/reset',
          handleCodeInApp: true,
          androidPackageName: 'com.example.project_1',
          androidInstallApp: true,
          androidMinimumVersion: '1',
          iOSBundleId: 'com.example.project_1',
        );
        await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email, actionCodeSettings: actionSettings);
      } catch (e) {
        // Fallback: try sending without explicit action settings
        await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      }

      // Mark a flag so the app can detect resume after the user clicks the link
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('password_reset_in_progress', true);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Password reset sent'),
          content: Text('A password reset email has been sent to $email. Open the email and click the link to reset your password. When you return to the app it will prompt you and then take you to the sign in page.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // After acknowledging, pop back to auth screen
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to send reset email: $e')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Please enter your email';
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(v.trim())) {
                        // Use common simple email regex (keeps parity with other validators)
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}').hasMatch(v.trim())) {
                          return 'Enter a valid email';
                        }
                      }
                      return null;
                    },
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSending ? null : _sendReset,
                  child: _isSending ? const CircularProgressIndicator() : const Text('Send password reset email'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
