import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'password_reset_screen.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/user_provider.dart';
import '../../models/chat_model.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedAiAgent = 'Ade';
  bool _isLoading = false;
  bool _isLoginMode = false;
  int _resendCooldown = 0; // seconds remaining
  Timer? _resendTimer;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 30]) {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown = _resendCooldown - 1;
        if (_resendCooldown <= 0) {
          _resendCooldown = 0;
          timer.cancel();
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // If the app set a flag after an in-app password reset, show sign-in mode
    // so the user can sign in with their new password.
    (() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final forceSignIn = prefs.getBool('force_sign_in_mode') ?? false;
        if (forceSignIn) {
          await prefs.remove('force_sign_in_mode');
          if (mounted) setState(() => _isLoginMode = true);
        }
      } catch (_) {}
    })();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // When the app resumes, check flows that may have completed in the email
      // app (email verification for sign-up, or password reset completion).
      _handleAppResume();
    }
  }

  Future<void> _handleAppResume() async {
    // Re-check email verification for sign-up flow
    try {
      await _checkEmailVerifiedAndProceed();
    } catch (_) {}

    // Check if a password reset was in progress (sent earlier). If so,
    // clear the flag and prompt the user to sign in with their new password.
    try {
      final prefs = await SharedPreferences.getInstance();
      final inProgress = prefs.getBool('password_reset_in_progress') ?? false;
      if (inProgress) {
        await prefs.remove('password_reset_in_progress');
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Password reset completed?'),
            content: const Text('If you have completed the password reset flow in your email, please sign in using your new password.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        setState(() {
          _isLoginMode = true; // ensure sign-in form is shown
        });
      }
    } catch (_) {}
  }

  @override
  void deactivate() {
    WidgetsBinding.instance.removeObserver(this);
    super.deactivate();
  }

  // sign-up handled by _submitAuth

  Future<void> _submitAuth() async {
    if (!_formKey.currentState!.validate()) return;

  setState(() => _isLoading = true);
  final userProvider = Provider.of<UserProvider>(context, listen: false);
    final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);

    try {
      if (_isLoginMode) {
        await userProvider.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        // On successful sign-in, go to main
        appStateProvider.login();
      } else {
        await userProvider.createUser(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          name: _nameController.text.trim(),
          selectedAiAgent: _selectedAiAgent,
        );
        // Firebase will send a verification email to the user. Show a modal with next steps.
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text('Verify your email'),
              content: Text('A verification link has been sent to ${_emailController.text.trim()}. Open your email app and click the link. Then return here and tap "I clicked the link" to continue.'),
              actions: [
                TextButton(
                  onPressed: _resendCooldown > 0
                      ? null
                      : () async {
                          // Resend verification email
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.of(context).pop();
                          setState(() => _isLoading = true);
                          try {
                            await Provider.of<UserProvider>(context, listen: false).resendEmailVerification();
                            _startResendCooldown(30);
                            if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Verification email resent.')));
                          } catch (e) {
                            if (mounted) messenger.showSnackBar(SnackBar(content: Text('Failed to resend: $e')));
                          } finally {
                            if (mounted) setState(() => _isLoading = false);
                          }
                        },
                  child: _resendCooldown > 0
                      ? Text('Resend (${_resendCooldown}s)')
                      : const Text('Resend verification email'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await _openEmailApp();
                  },
                  child: const Text('Open Email App'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _checkEmailVerifiedAndProceed();
                  },
                  child: const Text('I clicked the link'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Authentication error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // OTP flow removed. No local OTP verification.


  Future<void> _checkEmailVerifiedAndProceed() async {
    final messenger = ScaffoldMessenger.of(context);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);
    setState(() => _isLoading = true);
    try {
      // reload firebase user
      final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (fbUser == null) {
        if (mounted) messenger.showSnackBar(const SnackBar(content: Text('No signed-in user found.')));
        return;
      }
      await fbUser.reload();
      final reloaded = fb_auth.FirebaseAuth.instance.currentUser;
      if (reloaded != null && reloaded.emailVerified) {
        // refresh provider data and proceed
        await userProvider.refreshFromFirebase();
        appStateProvider.login();
      } else {
        if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Email not yet verified. Please click the link in your email.')));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Verification check failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openEmailApp() async {
    try {
      // Try to open the default email app on Android via intent. For other platforms, instruct the user.
      // android_intent_plus is available in pubspec and will be used on Android devices.
      // We avoid importing at top-level to keep platform checks simple.
      if (Theme.of(context).platform == TargetPlatform.android) {
        try {
          final intent = AndroidIntent(
            action: 'android.intent.action.MAIN',
            category: 'android.intent.category.APP_EMAIL',
          );
          await intent.launch();
          return;
        } catch (e) {
          // fallthrough to url_launcher fallback
        }
      }

      // Fallback: open a mailto: link which will open the user's mail client on most platforms
      final mailto = Uri(scheme: 'mailto', path: _emailController.text.trim());
      if (await canLaunchUrl(mailto)) {
        await launchUrl(mailto);
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please open your email app and click the verification link.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to open email app: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                
                // Logo and Title
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/images/watchtower.png',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Icon(
                                Icons.security,
                                size: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Watchtower App',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your account to start your digital wellness journey',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Name Field
                  // Name Field (only for sign-up)
                  if (!_isLoginMode)
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter your full name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (!_isLoginMode && (value == null || value.trim().isEmpty)) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                
                const SizedBox(height: 20),
                
                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 12),

                // Password Field (for sign-up/login) - moved under Email
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter a password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                // Google sign button moved below the submit button (see later).

                const SizedBox(height: 20),

                // Email verification flow uses Firebase email links. OTP flow removed.

                // AI Agent Selection (only shown during sign-up)
                if (!_isLoginMode) ...[
                  Text(
                    'Choose Your AI Wellness Coach',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildAiAgentOption(
                    agent: AiAgent.ade,
                    isSelected: _selectedAiAgent == 'Ade',
                    onTap: () => setState(() => _selectedAiAgent = 'Ade'),
                  ),
                  const SizedBox(height: 12),
                  _buildAiAgentOption(
                    agent: AiAgent.shalewa,
                    isSelected: _selectedAiAgent == 'Chidinma',
                    onTap: () => setState(() => _selectedAiAgent = 'Chidinma'),
                  ),
                ],
                
                const SizedBox(height: 40),
                
                  // Submit Button (Sign Up / Sign In)
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submitAuth,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(_isLoginMode ? 'Sign In' : 'Create Account'),
                  ),

                  const SizedBox(height: 12),

                  // Google Sign-Up / Sign-In button (position swapped: appears after the primary submit button)
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            final messenger = ScaffoldMessenger.of(context);
                            // capture a reference to the BuildContext before any awaits so
                            // we don't use the StatefulWidget's `context` across async gaps
                            final dialogContext = context;
                            try {
                              final userProvider = Provider.of<UserProvider>(context, listen: false);
                              final appStateProvider = Provider.of<AppStateProvider>(context, listen: false);

                              // Let GoogleSignIn present the account chooser and return the selected account
                              final googleSignIn = GoogleSignIn();
                              // Force account chooser by signing out cached account first
                              try {
                                await googleSignIn.signOut();
                              } catch (_) {}
                              final googleUser = await googleSignIn.signIn();
                              if (googleUser == null) {
                                // user cancelled account selection
                                return;
                              }

                              final email = googleUser.email;
                              // Debug: log selected Google account email
                              debugPrint('AuthScreen: selected Google account -> $email');

                              // Check if a user profile already exists for this email in Firestore
                              final query = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).limit(1).get();
                              debugPrint('AuthScreen: Firestore users query for $email returned ${query.docs.length} docs');
                              final exists = query.docs.isNotEmpty;

                              if (!_isLoginMode) {
                                // User clicked 'Sign up with Google'
                                if (exists) {
                                  // Offer to switch to Sign In and automatically retry the Google flow
                                  if (!mounted) return;
                                  final shouldSwitch = await showDialog<bool>(
                                    context: dialogContext,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Account already exists'),
                                      content: Text('An account using $email already exists. Would you like to switch to Sign in and continue?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: const Text('Switch to Sign In'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (!mounted) return;
                                  if (shouldSwitch == true) {
                                    // switch to login mode but do NOT sign the user in automatically here.
                                    setState(() => _isLoginMode = true);
                                  }
                                  // In sign-up flow we must never log an existing user in. Stop here and let the user
                                  // explicitly tap "Sign in with Google" to authenticate.
                                  return;
                                }

                                // Proceed to sign in with Google using the already-selected account (avoid showing chooser twice)
                                final googleAuth = await googleUser.authentication;
                                final credential = fb_auth.GoogleAuthProvider.credential(
                                  accessToken: googleAuth.accessToken,
                                  idToken: googleAuth.idToken,
                                );
                                await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
                                await userProvider.refreshFromFirebase();
                                appStateProvider.login();
                              } else {
                                // User clicked 'Sign in with Google'
                                if (!exists) {
                                  // Offer to switch to Sign Up and automatically retry the Google flow
                                  if (!mounted) return;
                                  final shouldGoSignup = await showDialog<bool>(
                                    context: dialogContext,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('No account found'),
                                      content: Text('No account is registered with $email. Would you like to switch to Sign up and continue?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(true),
                                          child: const Text('Go to Sign Up'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (!mounted) return;
                                  if (shouldGoSignup != true) {
                                    return;
                                  }

                                  // switch to signup mode and proceed to sign-up with the selected Google account
                                  setState(() => _isLoginMode = false);
                                  // proceed to sign-in below (fallthrough) which will create the user profile
                                }

                                // Proceed to sign in using the already-selected Google account
                                final googleAuth = await googleUser.authentication;
                                final credential = fb_auth.GoogleAuthProvider.credential(
                                  accessToken: googleAuth.accessToken,
                                  idToken: googleAuth.idToken,
                                );
                                await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
                                await userProvider.refreshFromFirebase();
                                appStateProvider.login();
                              }
                            } catch (e) {
                              if (mounted) {
                                messenger.showSnackBar(SnackBar(content: Text('Google auth error: $e')));
                              }
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    icon: const Icon(Icons.login),
                    label: Text(_isLoginMode ? 'Sign in with Google' : 'Sign up with Google'),
                  ),

                  const SizedBox(height: 8),
                  if (_isLoginMode)
                    Center(
                      child: TextButton(
                        onPressed: () async {
                          // Navigate to password reset screen
                          if (!mounted) return;
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PasswordResetScreen(),
                          ));
                        },
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                      child: Text(_isLoginMode ? 'Don\'t have an account? Sign up' : 'Already have an account? Sign in'),
                    ),
                  ),
                  const SizedBox(height: 8),
                
                const SizedBox(height: 20),

                // Removed duplicate password & Google button (kept the first instances earlier in the form)
                
                // Terms and Privacy
                Text(
                  'By creating an account, you agree to our Terms of Service and Privacy Policy. You\'ll start with a 14-day free trial.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAiAgentOption({
    required AiAgent agent,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
      color: isSelected 
        ? Theme.of(context).colorScheme.primary.withAlpha((0.1 * 255).round())
        : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
      color: isSelected 
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.withAlpha((0.3 * 255).round()),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(
                Icons.psychology,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 24,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Agent Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected 
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    agent.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: agent.specialties.take(2).map((specialty) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
              color: isSelected 
                ? Theme.of(context).colorScheme.primary.withAlpha((0.2 * 255).round())
                : Colors.grey.withAlpha((0.2 * 255).round()),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          specialty,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: isSelected 
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey[600],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            
            // Selection Indicator
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

