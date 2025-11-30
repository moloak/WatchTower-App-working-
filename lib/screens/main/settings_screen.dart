import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/usage_provider.dart';
import '../../models/user_model.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer3<AppStateProvider, UserProvider, UsageProvider>(
        builder: (context, appState, userProvider, usageProvider, child) {
          final user = userProvider.user;
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
                // User Profile Section
                _buildSection(
                  title: 'Profile',
                  children: [
                    _buildProfileCard(context, user),
                  ],
                ),
              
              const SizedBox(height: 24),
              
              // App Settings Section
              _buildSection(
                title: 'App Settings',
                children: [
                  _buildSwitchTile(
                    title: 'Notifications',
                    subtitle: 'Receive usage alerts and reminders',
                    value: user.preferences.notificationsEnabled,
                    onChanged: (value) => _updatePreference(
                      userProvider,
                      user.preferences.copyWith(notificationsEnabled: value),
                    ),
                  ),
                  _buildSwitchTile(
                    title: 'Overlay Warnings',
                    subtitle: 'Show overlay notifications on other apps',
                    value: user.preferences.overlayEnabled,
                    onChanged: (value) => _updatePreference(
                      userProvider,
                      user.preferences.copyWith(overlayEnabled: value),
                    ),
                  ),
                  _buildSwitchTile(
                    title: 'Weekly Reports',
                    subtitle: 'Receive weekly usage analytics',
                    value: user.preferences.weeklyReportsEnabled,
                    onChanged: (value) => _updatePreference(
                      userProvider,
                      user.preferences.copyWith(weeklyReportsEnabled: value),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Appearance Section
              _buildSection(
                title: 'Appearance',
                children: [
                  _buildListTile(
                    title: 'Theme',
                    subtitle: _getThemeName(appState.themeMode),
                    leading: Icons.palette,
                    onTap: () => _showThemeDialog(context, appState),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Permissions Section
              _buildSection(
                title: 'Permissions',
                children: [
                  _buildPermissionTile(
                    title: 'Usage Access',
                    subtitle: 'Monitor app usage time',
                    isGranted: usageProvider.hasPermissions,
                    onTap: () => _showUsageAccessDialog(context, usageProvider),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Subscription Section removed per product request
              // (Previously showed trial/subscription status and Upgrade CTA.)
              const SizedBox(height: 24),
              
              // Data Management Section
              _buildSection(
                title: 'Data Management',
                children: [
                  _buildListTile(
                    title: 'Export Data',
                    subtitle: 'Download your usage data',
                    leading: Icons.download,
                    onTap: () => _exportData(context),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Account Section
              _buildSection(
                title: 'Account',
                children: [
                  _buildListTile(
                    title: 'Sign Out',
                    subtitle: 'Sign out of your account',
                    leading: Icons.logout,
                    onTap: () => _showSignOutDialog(context, appState, userProvider),
                  ),
                ],
              ),
              
              const SizedBox(height: 100), // Bottom padding
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildProfileCard(BuildContext context, UserModel user) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              user.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha((0.1 * 255).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'AI Coach: ${user.selectedAiAgent}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildListTile({
    required String title,
    required String subtitle,
    required IconData leading,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(leading),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required String subtitle,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        isGranted ? Icons.check_circle : Icons.error,
        color: isGranted ? Colors.green : Colors.red,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: isGranted 
          ? const Text('Granted', style: TextStyle(color: Colors.green))
          : ElevatedButton(
              onPressed: onTap,
              child: const Text('Grant'),
            ),
    );
  }

  void _showUsageAccessDialog(BuildContext context, UsageProvider usageProvider) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grant Usage Access'),
        content: const Text(
          'Watchtower needs Usage Access to monitor app time.\n\n'
          'You will be taken to the Android Usage Access settings.\n'
          'Enable "Permit usage access" for Watchtower, then return to the app.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final granted = await usageProvider.requestPermissions();
              final messenger = ScaffoldMessenger.of(context);
              if (granted) {
                messenger.showSnackBar(const SnackBar(content: Text('Usage Access granted')));
              } else {
                messenger.showSnackBar(const SnackBar(content: Text('Usage Access not granted')));
              }
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }


  String _getThemeName(ThemeMode themeMode) {
    switch (themeMode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _updatePreference(UserProvider userProvider, UserPreferences preferences) {
    userProvider.updatePreferences(preferences);
  }

  void _showThemeDialog(BuildContext context, AppStateProvider appState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('Light'),
              value: ThemeMode.light,
              groupValue: appState.themeMode,
              onChanged: (value) {
                if (value != null) {
                  appState.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('Dark'),
              value: ThemeMode.dark,
              groupValue: appState.themeMode,
              onChanged: (value) {
                if (value != null) {
                  appState.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('System'),
              value: ThemeMode.system,
              groupValue: appState.themeMode,
              onChanged: (value) {
                if (value != null) {
                  appState.setThemeMode(value);
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _exportData(BuildContext context) {
    // TODO: Implement data export
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Data export feature coming soon'),
      ),
    );
  }

  void _showSignOutDialog(
    BuildContext context,
    AppStateProvider appState,
    UserProvider userProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              userProvider.signOut();
              appState.logout();
              Navigator.pop(context);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
