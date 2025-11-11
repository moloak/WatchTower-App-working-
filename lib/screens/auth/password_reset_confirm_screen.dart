import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/app_state_provider.dart';

class PasswordResetConfirmScreen extends StatefulWidget {
  final String code;
  const PasswordResetConfirmScreen({super.key, required this.code});

  @override
  State<PasswordResetConfirmScreen> createState() => _PasswordResetConfirmScreenState();
}

class _PasswordResetConfirmScreenState extends State<PasswordResetConfirmScreen> {
  String? _email;
  bool _loading = true;
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _verifyCode();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    try {
      final email = await fb_auth.FirebaseAuth.instance.verifyPasswordResetCode(widget.code);
      setState(() {
        _email = email;
        _loading = false;
      });
    } catch (e) {
      // invalid or expired code
      // Capture app state before awaiting UI work to avoid using BuildContext across async gaps
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Invalid link'),
            content: const Text('This password reset link is invalid or has expired.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          ),
        );
        if (!mounted) return;
        // return to auth
        appState.setAppState(AppState.auth);
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _submitNewPassword() async {
    if (!_formKey.currentState!.validate()) return;
    final pwd = _passwordController.text.trim();
    setState(() => _loading = true);
    try {
      await fb_auth.FirebaseAuth.instance.confirmPasswordReset(code: widget.code, newPassword: pwd);

      // After successful reset, set a flag so AuthScreen shows sign-in mode
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_sign_in_mode', true);

      // Capture app state before awaiting UI operations to avoid using BuildContext after awaits
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Password changed'),
            content: const Text('Your password has been changed. Please sign in using your new password.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          ),
        );

        if (!mounted) return;
        // Navigate back to the root and show auth
        appState.setAppState(AppState.auth);
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to reset password: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Resetting password for: ${_email ?? ''}'),
                    const SizedBox(height: 20),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'New password'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Enter a password';
                              if (v.trim().length < 6) return 'Password must be at least 6 characters';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Confirm password'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Confirm your password';
                              if (v.trim() != _passwordController.text.trim()) return 'Passwords do not match';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _loading ? null : _submitNewPassword,
                            child: _loading ? const CircularProgressIndicator() : const Text('Set new password'),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),
      ),
    );
  }
}
