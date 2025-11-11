class UserModel {
  final String id;
  final String email;
  final String name;
  final String selectedAiAgent; // 'Ade' or 'Chidinma'
  final DateTime createdAt;
  final DateTime? trialEndDate;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionEndDate;
  final Map<String, Duration> weeklyAppLimits;
  final bool emailVerified;
  final bool hasCompletedOnboarding;
  final UserPreferences preferences;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.selectedAiAgent,
    required this.createdAt,
    this.trialEndDate,
    required this.subscriptionStatus,
    this.subscriptionEndDate,
    this.weeklyAppLimits = const {},
    this.emailVerified = false,
    this.hasCompletedOnboarding = false,
    this.preferences = const UserPreferences(),
  });

  bool get isOnTrial => subscriptionStatus == SubscriptionStatus.trial;
  bool get isSubscribed => subscriptionStatus == SubscriptionStatus.active;
  bool get isTrialExpired => isOnTrial && 
      trialEndDate != null && 
      DateTime.now().isAfter(trialEndDate!);
  bool get hasActiveSubscription => isSubscribed && 
      subscriptionEndDate != null && 
      DateTime.now().isBefore(subscriptionEndDate!);

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    String? selectedAiAgent,
    DateTime? createdAt,
    DateTime? trialEndDate,
    SubscriptionStatus? subscriptionStatus,
    DateTime? subscriptionEndDate,
    Map<String, Duration>? weeklyAppLimits,
    bool? emailVerified,
    bool? hasCompletedOnboarding,
    UserPreferences? preferences,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      selectedAiAgent: selectedAiAgent ?? this.selectedAiAgent,
      createdAt: createdAt ?? this.createdAt,
      trialEndDate: trialEndDate ?? this.trialEndDate,
      subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
      subscriptionEndDate: subscriptionEndDate ?? this.subscriptionEndDate,
      weeklyAppLimits: weeklyAppLimits ?? this.weeklyAppLimits,
      emailVerified: emailVerified ?? this.emailVerified,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      preferences: preferences ?? this.preferences,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'selectedAiAgent': selectedAiAgent,
      'createdAt': createdAt.toIso8601String(),
      'trialEndDate': trialEndDate?.toIso8601String(),
      'subscriptionStatus': subscriptionStatus.toString(),
      'subscriptionEndDate': subscriptionEndDate?.toIso8601String(),
      'weeklyAppLimits': weeklyAppLimits.map((key, value) => MapEntry(key, value.inMinutes)),
      'emailVerified': emailVerified,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'preferences': preferences.toJson(),
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      name: json['name'],
      selectedAiAgent: json['selectedAiAgent'],
      createdAt: DateTime.parse(json['createdAt']),
      trialEndDate: json['trialEndDate'] != null 
          ? DateTime.parse(json['trialEndDate']) 
          : null,
      subscriptionStatus: SubscriptionStatus.values.firstWhere(
        (e) => e.toString() == json['subscriptionStatus'],
        orElse: () => SubscriptionStatus.trial,
      ),
      subscriptionEndDate: json['subscriptionEndDate'] != null 
          ? DateTime.parse(json['subscriptionEndDate']) 
          : null,
      weeklyAppLimits: (json['weeklyAppLimits'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, Duration(minutes: value))) ?? {},
      emailVerified: json['emailVerified'] ?? false,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] ?? false,
      preferences: UserPreferences.fromJson(json['preferences'] ?? {}),
    );
  }
}

enum SubscriptionStatus {
  trial,
  active,
  expired,
  cancelled,
}

class UserPreferences {
  final bool notificationsEnabled;
  final bool overlayEnabled;
  final bool weeklyReportsEnabled;
  final String theme; // 'light', 'dark', 'system'
  final String language;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final Duration reminderInterval; // How often to show usage reminders

  const UserPreferences({
    this.notificationsEnabled = true,
    this.overlayEnabled = true,
    this.weeklyReportsEnabled = true,
    this.theme = 'system',
    this.language = 'en',
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.reminderInterval = const Duration(minutes: 30),
  });

  UserPreferences copyWith({
    bool? notificationsEnabled,
    bool? overlayEnabled,
    bool? weeklyReportsEnabled,
    String? theme,
    String? language,
    bool? soundEnabled,
    bool? vibrationEnabled,
    Duration? reminderInterval,
  }) {
    return UserPreferences(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      weeklyReportsEnabled: weeklyReportsEnabled ?? this.weeklyReportsEnabled,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      reminderInterval: reminderInterval ?? this.reminderInterval,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notificationsEnabled': notificationsEnabled,
      'overlayEnabled': overlayEnabled,
      'weeklyReportsEnabled': weeklyReportsEnabled,
      'theme': theme,
      'language': language,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
      'reminderInterval': reminderInterval.inMinutes,
    };
  }

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      notificationsEnabled: json['notificationsEnabled'] ?? true,
      overlayEnabled: json['overlayEnabled'] ?? true,
      weeklyReportsEnabled: json['weeklyReportsEnabled'] ?? true,
      theme: json['theme'] ?? 'system',
      language: json['language'] ?? 'en',
      soundEnabled: json['soundEnabled'] ?? true,
      vibrationEnabled: json['vibrationEnabled'] ?? true,
      reminderInterval: Duration(minutes: json['reminderInterval'] ?? 30),
    );
  }
}

