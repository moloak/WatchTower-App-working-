import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/app_state_provider.dart';
import 'providers/user_provider.dart';
import 'providers/usage_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/auth_screen.dart';
// password reset confirm screen import removed because dynamic link handling is currently disabled
// import 'screens/auth/password_reset_confirm_screen.dart';
import 'screens/main/main_navigation.dart';
import 'services/notification_service.dart';
// Unused services removed: app_usage_service, overlay_service
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase and services, but don't crash the app if they fail during local/dev runs
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    // Log and continue; Firebase may not be available in local/test environments
    // ignore: avoid_print
    debugPrint('Firebase initialization failed: $e\n$st');
  }

  try {
    await NotificationService().initialize();
  } catch (e, st) {
    // ignore: avoid_print
    debugPrint('NotificationService initialization failed: $e\n$st');
  }

  runApp(const WatchtowerApp());
}

class WatchtowerApp extends StatefulWidget {
  const WatchtowerApp({super.key});

  @override 
  State<WatchtowerApp> createState() => _WatchtowerAppState();
}

class _WatchtowerAppState extends State<WatchtowerApp> {
  @override
  void initState() {
    super.initState();
    // Deep-link handling (app_links) was removed for compatibility with
    // the currently pinned package versions in this workspace. If you
    // prefer OS-level deep links, re-add app_links and adapt the
    // initialization per the package API.
  }
  // _handleDeepLink intentionally removed; restore if re-adding app_links.

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => UsageProvider()),
      ],
      child: Consumer<AppStateProvider>(
        builder: (context, appState, child) {
          return MaterialApp(
            title: 'Watchtower',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appState.themeMode,
            home: const AppRouter(),
          );
        },
      ),
    );
  }
}

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        switch (appState.appState) {
          case AppState.splash:
            return const SplashScreen();
          case AppState.onboarding:
            return const OnboardingScreen();
          case AppState.auth:
            return const AuthScreen();
          case AppState.main:
            return const MainNavigation();
        }
      },
    );
  }
}