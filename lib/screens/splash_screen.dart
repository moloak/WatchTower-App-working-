import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late Animation<double> _logoAnimation;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _logoAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutBack,
    ));

    // Wait for provider initialization to complete before starting animations so
    // the provider's state (onboarding/auth/main) is already decided.
    _waitForInitializationAndStart();
  }

  Future<void> _waitForInitializationAndStart() async {
    try {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      await appState.initializationComplete;
    } catch (e) {
      // ignore errors and continue with animations
    }
    _startAnimations();
  }

  void _startAnimations() async {
    await _logoController.forward();

    // Keep splash total visible for ~2.5 seconds from start
    await Future.delayed(const Duration(milliseconds: 1250));

    if (mounted) {
      final appState = Provider.of<AppStateProvider>(context, listen: false);
      // Only move to onboarding if the provider still considers us in the splash state.
      // This avoids overwriting the provider's initial decision (auth/main) based on saved prefs.
      if (appState.appState == AppState.splash) {
        appState.setAppState(AppState.onboarding);
      }
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _logoAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _logoAnimation.value,
              child: child,
            );
          },
          child: Container(
            width: 220,
            height: 220,
            alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/watchtower.png',
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) {
                    // Fallback to an icon if the asset is missing
                    return Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.shield, size: 84, color: Colors.black),
                    );
                  },
                ),
              ),
          ),
        ),
      ),
    );
  }
}
