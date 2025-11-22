import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';
import '../services/payments_service.dart';
import '../models/chat_model.dart';

class UserProvider extends ChangeNotifier {
  UserModel? _user;
  List<ChatSession> _chatSessions = [];
  bool _isLoading = false;

  UserModel? get user => _user;
  List<ChatSession> get chatSessions => _chatSessions;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;

  UserProvider() {
    _loadUserData();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp();
      // If user is already signed in via Firebase, sync profile -- but
      // respect explicit sign-out by the user so we don't auto re-login.
      final prefs = await SharedPreferences.getInstance();
      final explicitlySignedOut = prefs.getBool('explicitly_signed_out') ?? false;
      if (!explicitlySignedOut) {
        final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
        if (fbUser != null) {
          await _syncFromFirebaseUser(fbUser);
        }
      }
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }

  Future<void> _syncFromFirebaseUser(fb_auth.User fbUser) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(fbUser.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        _user = UserModel.fromJson(data);
        await _saveUserData();
        notifyListeners();
      } else {
        // Create profile document if missing
        final now = DateTime.now();
        final userModel = UserModel(
          id: fbUser.uid,
          email: fbUser.email ?? '',
          name: fbUser.displayName ?? '',
          selectedAiAgent: _user?.selectedAiAgent ?? 'Ade',
          createdAt: now,
          trialEndDate: now.add(const Duration(days: 14)),
          subscriptionStatus: SubscriptionStatus.trial,
          hasCompletedOnboarding: true,
        );
        _user = userModel;
        final userJson = userModel.toJson();
        // Add userId field for Firestore security rules
        userJson['userId'] = fbUser.uid;
        await FirebaseFirestore.instance.collection('users').doc(fbUser.uid).set(userJson);
        await _saveUserData();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error syncing firebase user: $e');
      rethrow;
    }
  }

  /// Public helper to refresh local profile from the currently signed-in Firebase user.
  Future<void> refreshFromFirebase() async {
    try {
      final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        await _syncFromFirebaseUser(fbUser);
      }
    } catch (e) {
      debugPrint('Error refreshing from firebase: $e');
    }
  }

  Future<void> _loadUserData() async {
    _setLoading(true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('user_data');
      final sessionsJson = prefs.getString('chat_sessions');
      
      if (userJson != null) {
        final userData = json.decode(userJson);
        _user = UserModel.fromJson(userData);
      }
      
      if (sessionsJson != null) {
        final sessionsData = json.decode(sessionsJson) as List;
        _chatSessions = sessionsData
            .map((session) => ChatSession.fromJson(session))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required String selectedAiAgent,
  }) async {
    _setLoading(true);

    try {
      // Create user via Firebase Auth (email/password) and create Firestore profile
      final fbAuth = fb_auth.FirebaseAuth.instance;
  final userCred = await fbAuth.createUserWithEmailAndPassword(email: email, password: password);
      // NOTE: we create with a temporary password placeholder — UI should collect password during signup. Update accordingly.
      final fbUser = userCred.user!;
      final now = DateTime.now();

      final userModel = UserModel(
        id: fbUser.uid,
        email: email,
        name: name,
        selectedAiAgent: selectedAiAgent,
        createdAt: now,
        trialEndDate: now.add(const Duration(days: 14)),
        subscriptionStatus: SubscriptionStatus.trial,
        hasCompletedOnboarding: true,
      );

      _user = userModel;
      final userJson = userModel.toJson();
      // Add userId field for Firestore security rules
      userJson['userId'] = fbUser.uid;
      await FirebaseFirestore.instance.collection('users').doc(fbUser.uid).set(userJson);
      // mark email_verified false until user clicks verification link
      await FirebaseFirestore.instance.collection('users').doc(fbUser.uid).update({'email_verified': false});
      // Trigger Firebase Auth email verification link (use resend helper)
      try {
        await resendEmailVerification(fbUser: fbUser);
      } catch (e) {
        debugPrint('Failed to send Firebase email verification link: $e');
      }
      await _saveUserData();
      // Clear explicit sign-out flag when creating/signing-in
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('explicitly_signed_out', false);
      } catch (_) {}
      notifyListeners();
    } catch (e) {
      debugPrint('Error creating user: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// Sends (or resends) the Firebase email verification link for the current user.
  /// If [fbUser] is provided it will be used; otherwise the currently signed-in
  /// Firebase user will be resolved and used.
  Future<void> resendEmailVerification({fb_auth.User? fbUser}) async {
    try {
      final auth = fb_auth.FirebaseAuth.instance;
      final userToUse = fbUser ?? auth.currentUser;
      if (userToUse == null) {
        debugPrint('No Firebase user available to send verification to.');
        throw Exception('No signed in user');
      }
      await userToUse.sendEmailVerification();
      debugPrint('Verification email sent to ${userToUse.email}');
    } catch (e) {
      debugPrint('Error sending verification email: $e');
      rethrow;
    }
  }



  // Email sign-in
  Future<void> signInWithEmail({required String email, required String password}) async {
    _setLoading(true);
    try {
      final userCred = await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      final fbUser = userCred.user!;
      await _syncFromFirebaseUser(fbUser);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('explicitly_signed_out', false);
      } catch (_) {}
    } catch (e) {
      debugPrint('Email sign-in error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // Google sign-in
  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      final googleSignIn = GoogleSignIn();
      // Force account chooser by signing out any previously cached account
      try {
        await googleSignIn.signOut();
      } catch (_) {}
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return; // canceled
      final googleAuth = await googleUser.authentication;
      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
      final fbUser = userCred.user!;
      await _syncFromFirebaseUser(fbUser);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('explicitly_signed_out', false);
      } catch (_) {}
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> signOut() async {
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('explicitly_signed_out', true);
    } catch (_) {}
    await logout();
  }

  Future<void> updateUser(UserModel updatedUser) async {
    _user = updatedUser;
    await _saveUserData();
    notifyListeners();
  }

  Future<void> updateSubscription({
    required SubscriptionStatus status,
    DateTime? endDate,
  }) async {
    if (_user == null) return;
    
    _user = _user!.copyWith(
      subscriptionStatus: status,
      subscriptionEndDate: endDate,
    );
    
    await _saveUserData();
    notifyListeners();
  }

  Future<void> updatePreferences(UserPreferences preferences) async {
    if (_user == null) return;
    
    _user = _user!.copyWith(preferences: preferences);
    await _saveUserData();
    notifyListeners();
  }

  Future<void> updateWeeklyAppLimits(Map<String, Duration> limits) async {
    if (_user == null) return;
    
    _user = _user!.copyWith(weeklyAppLimits: limits);
    await _saveUserData();
    notifyListeners();
  }

  /// Verify a payment reference with the backend and activate user's subscription if valid.
  /// This calls the PaymentsService which in turn calls the server-side verification.
  Future<void> verifyPaymentAndActivate(String reference) async {
    if (_user == null) throw Exception('No user');
    try {
      // Call server via PaymentsService to verify transaction
      final success = await PaymentsService().verifyTransaction(reference: reference);
      if (!success) throw Exception('Payment verification failed');

      // On success, update Firestore subscription fields
      final now = DateTime.now();
      final endDate = now.add(const Duration(days: 30)); // assume monthly; server should send exact endDate in production
      _user = _user!.copyWith(subscriptionStatus: SubscriptionStatus.active, subscriptionEndDate: endDate);
      await FirebaseFirestore.instance.collection('users').doc(_user!.id).update({
        'subscriptionStatus': 'active',
        'subscriptionEndDate': endDate.toIso8601String(),
      });
      await _saveUserData();
      notifyListeners();
    } catch (e) {
      debugPrint('verifyPaymentAndActivate error: $e');
      rethrow;
    }
  }

  Future<void> addChatSession(ChatSession session) async {
    _chatSessions.insert(0, session);
    await _saveChatSessions();
    notifyListeners();
  }

  Future<void> updateChatSession(ChatSession session) async {
    final index = _chatSessions.indexWhere((s) => s.id == session.id);
    if (index != -1) {
      _chatSessions[index] = session;
      await _saveChatSessions();
      notifyListeners();
    }
  }

  Future<void> deleteChatSession(String sessionId) async {
    _chatSessions.removeWhere((session) => session.id == sessionId);
    await _saveChatSessions();
    notifyListeners();
  }

  ChatSession? getChatSession(String sessionId) {
    try {
      return _chatSessions.firstWhere((session) => session.id == sessionId);
    } catch (e) {
      return null;
    }
  }

  List<ChatSession> getChatSessionsByCategory(ChatCategory category) {
    return _chatSessions.where((session) => session.category == category).toList();
  }

  Future<void> logout() async {
    _user = null;
    _chatSessions.clear();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.remove('chat_sessions');
    } catch (e) {
      debugPrint('Error clearing user data: $e');
    }
    
    notifyListeners();
  }

  Future<void> _saveUserData() async {
    if (_user == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = json.encode(_user!.toJson());
      await prefs.setString('user_data', userJson);
    } catch (e) {
      debugPrint('Error saving user data: $e');
    }
  }

  Future<void> _saveChatSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionsJson = json.encode(_chatSessions.map((s) => s.toJson()).toList());
      await prefs.setString('chat_sessions', sessionsJson);
    } catch (e) {
      debugPrint('Error saving chat sessions: $e');
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  // Note: user IDs are provided by Firebase Auth; no local ID generator needed.

  // Helper methods
  bool get isOnTrial => _user?.isOnTrial ?? false;
  bool get isSubscribed => _user?.isSubscribed ?? false;
  bool get hasActiveSubscription => _user?.hasActiveSubscription ?? false;
  String get selectedAiAgent => _user?.selectedAiAgent ?? 'Ade';
  
  Duration? getTrialTimeRemaining() {
    if (_user?.trialEndDate == null) return null;
    final remaining = _user!.trialEndDate!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
  
  Duration? getSubscriptionTimeRemaining() {
    if (_user?.subscriptionEndDate == null) return null;
    final remaining = _user!.subscriptionEndDate!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

