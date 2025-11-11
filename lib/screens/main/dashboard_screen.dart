import 'package:flutter/material.dart';
// debug imports removed
import 'package:provider/provider.dart';
// import 'package:intl/intl.dart'; // unused
import '../../providers/user_provider.dart';
import '../payments/subscription_screen.dart';
import '../../providers/usage_provider.dart';
import '../../models/app_usage_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final usageProvider = Provider.of<UsageProvider>(context, listen: false);
      usageProvider.loadWeeklyUsage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          Consumer<UserProvider>(
            builder: (context, userProvider, child) {
              if (userProvider.user?.isOnTrial == true) {
                return Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Trial',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Removed debug test button for production
        ],
      ),
      body: Consumer2<UserProvider, UsageProvider>(
        builder: (context, userProvider, usageProvider, child) {
          final user = userProvider.user;
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              await usageProvider.loadWeeklyUsage();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Section
                  _buildWelcomeSection(user.name, user.selectedAiAgent),
                  
                  const SizedBox(height: 24),
                  
                  // Usage Overview
                  _buildUsageOverview(usageProvider),
                  
                  const SizedBox(height: 24),
                  
                  // Monitored Apps
                  _buildMonitoredAppsSection(usageProvider),
                  
                  const SizedBox(height: 24),
                  
                  // Quick Stats
                  _buildQuickStats(usageProvider),
                  
                  const SizedBox(height: 24),
                  
                  // Trial/Subscription Info
                  if (user.isOnTrial) _buildTrialInfo(user),
                  
                  const SizedBox(height: 100), // Bottom padding for FAB
                ],
              ),
            ),
          );
        },
      ),
      // Removed Add Apps FAB per design request
    );
  }

  Widget _buildWelcomeSection(String name, String aiAgent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back, $name!',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$aiAgent is here to support your digital wellness journey',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withAlpha((0.9 * 255).round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageOverview(UsageProvider usageProvider) {
    // If the app doesn't have usage access permission on Android, show a prompt
    if (!usageProvider.hasPermissions) {
      return Card(
        color: Colors.yellow[50],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Usage access required',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'To record app usage time the app needs permission to access usage data. Please grant Usage Access.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await usageProvider.requestPermissions();
                      // reload weekly usage after permission granted
                      await usageProvider.loadWeeklyUsage();
                      setState(() {});
                    },
                    child: const Text('Grant Usage Access'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () async {
                      // Try reloading monitored apps and usage stats
                      await usageProvider.loadWeeklyUsage();
                      setState(() {});
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final totalUsage = usageProvider.getTotalDailyUsage();
    final hours = totalUsage.inHours;
    final minutes = totalUsage.inMinutes % 60;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Today\'s Usage',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${hours}h ${minutes}m',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      Text(
                        'Total screen time',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha((0.1 * 255).round()),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Center(
                    child: Text(
                      '${usageProvider.monitoredApps.length}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Monitored Apps',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoredAppsSection(UsageProvider usageProvider) {
    final apps = usageProvider.monitoredApps.values.toList();
    
    if (apps.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.apps,
                size: 48,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No apps being monitored',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add apps to start tracking your digital wellness',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monitored Apps',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...apps.map((app) => _buildAppUsageCard(app)),
      ],
    );
  }

  Widget _buildAppUsageCard(AppUsageModel app) {
    final percentage = app.cappedUsagePercentage;
    final remainingTime = app.remainingTime;
    final hours = remainingTime.inHours;
    final minutes = remainingTime.inMinutes % 60;
    
    Color progressColor;
    if (percentage >= 90) {
      progressColor = Colors.red;
    } else if (percentage >= 60) {
      progressColor = Colors.orange;
    } else if (percentage >= 30) {
      progressColor = Colors.yellow[700]!;
    } else {
      progressColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // App Icon (use raw icon bytes when available)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: app.iconBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        app.iconBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Icon(Icons.apps),
            ),
            
            const SizedBox(width: 16),
            
            // App Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.appName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${app.currentUsage.inHours}h ${app.currentUsage.inMinutes % 60}m used',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (percentage / 100).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Percentage
            Column(
              children: [
                Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: progressColor,
                  ),
                ),
                Text(
                  '${hours}h ${minutes}m left',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStats(UsageProvider usageProvider) {
    final overusedApps = usageProvider.getOverusedApps();
    final appsNearLimit = usageProvider.getAppsNearLimit();
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.warning,
            title: 'Overused',
            value: '${overusedApps.length}',
            color: Colors.red,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.schedule,
            title: 'Near Limit',
            value: '${appsNearLimit.length}',
            color: Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            icon: Icons.check_circle,
            title: 'On Track',
            value: '${usageProvider.monitoredApps.length - overusedApps.length - appsNearLimit.length}',
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrialInfo(dynamic user) {
    final trialTimeRemaining = user.trialEndDate?.difference(DateTime.now());
    final daysLeft = trialTimeRemaining?.inDays ?? 0;
    
    return Card(
  color: Theme.of(context).colorScheme.primary.withAlpha((0.1 * 255).round()),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.star,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Free Trial',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              daysLeft > 0 
                  ? '$daysLeft days remaining in your free trial'
                  : 'Your free trial has ended',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                  );
                },
                child: const Text('Subscribe Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // debug helper UI removed
}