import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppState {
  splash,
  onboarding,
  auth,
  main,
}

class AppStateProvider extends ChangeNotifier {
  AppState _appState = AppState.splash;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isLoading = false;
  // Completer to signal when initialization is finished. SplashScreen can await this.
  final _initCompleter = Completer<void>();

  AppState get appState => _appState;
  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;

  AppStateProvider() {
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _setLoading(true);
    
    try {
      // Load saved preferences
      await _loadPreferences();
      
      // Check if user has completed onboarding
      final prefs = await SharedPreferences.getInstance();
      final hasCompletedOnboarding = prefs.getBool('has_completed_onboarding') ?? false;
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;
      
      if (!hasCompletedOnboarding) {
        // User hasn't gone through onboarding yet
        _appState = AppState.onboarding;
      } else if (isLoggedIn) {
        // User has completed onboarding and is logged in
        _appState = AppState.main;
      } else {
        // User has completed onboarding but not logged in
        _appState = AppState.auth;
      }
    } catch (e) {
      debugPrint('Error initializing app: $e');
      _appState = AppState.onboarding;
    } finally {
      _setLoading(false);
      // mark initialization complete for any waiters
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  /// A Future that completes when the provider has finished initialization.
  Future<void> get initializationComplete => _initCompleter.future;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt('theme_mode') ?? 0;
      _themeMode = ThemeMode.values[themeIndex];
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  void setAppState(AppState state) {
    _appState = state;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('theme_mode', mode.index);
    } catch (e) {
      debugPrint('Error saving theme mode: $e');
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_completed_onboarding', true);
      _appState = AppState.auth;
      notifyListeners();
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
    }
  }

  Future<void> login() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      _appState = AppState.main;
      notifyListeners();
    } catch (e) {
      debugPrint('Error logging in: $e');
    }
  }

  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', false);
      _appState = AppState.auth;
      notifyListeners();
    } catch (e) {
      debugPrint('Error logging out: $e');
    }
  }

  Future<void> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_completed_onboarding', false);
      _appState = AppState.onboarding;
      notifyListeners();
    } catch (e) {
      debugPrint('Error resetting onboarding: $e');
    }
  }
}

