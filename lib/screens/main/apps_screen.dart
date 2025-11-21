import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/usage_provider.dart';
import '../../services/app_usage_service.dart';

class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<InstalledApp> _installedApps = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
  }

  Future<void> _loadInstalledApps() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final usageProvider = Provider.of<UsageProvider>(context, listen: false);
      final apps = await usageProvider.usageService.getInstalledApps();

      setState(() {
        _installedApps = apps;
      });
    } catch (e) {
      debugPrint('Error loading apps: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _detectYouTube() async {
    setState(() => _isLoading = true);
    try {
      final usageProvider = Provider.of<UsageProvider>(context, listen: false);
      final found = await usageProvider.usageService.findInstalledAppByPackage('com.google.android.youtube');
      if (found != null) {
        // add to list if not already present
        final exists = _installedApps.any((a) => a.packageName == found.packageName);
        if (!exists) {
          setState(() {
            _installedApps.insert(0, found);
          });
        }
      }
    } catch (e) {
      debugPrint('Error detecting YouTube: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<InstalledApp> get _filteredApps {
    if (_searchQuery.isEmpty) return _installedApps;
    
    return _installedApps.where((app) =>
      app.appName.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Apps'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInstalledApps,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Detect YouTube on device',
            onPressed: _detectYouTube,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Consumer<UsageProvider>(
                    builder: (context, usageProvider, child) {
                      return _buildAppsList(usageProvider);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppsList(UsageProvider usageProvider) {
    final filteredApps = _filteredApps;
    
    if (filteredApps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.apps,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty 
                  ? 'No apps found'
                  : 'No apps match your search',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredApps.length,
      itemBuilder: (context, index) {
        final app = filteredApps[index];
        final isMonitored = usageProvider.monitoredApps.containsKey(app.packageName);
        
        return _buildAppCard(app, isMonitored, usageProvider);
      },
    );
  }

  Widget _buildAppCard(InstalledApp app, bool isMonitored, UsageProvider usageProvider) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: app.iconBytes != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    app.iconBytes!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                )
              : const Icon(Icons.apps),
        ),
        title: Text(
          app.appName,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          app.packageName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        trailing: isMonitored
            ? _buildMonitoredActions(app, usageProvider)
            : _buildAddButton(app, usageProvider),
      ),
    );
  }

  Widget _buildAddButton(InstalledApp app, UsageProvider usageProvider) {
    return ElevatedButton(
      onPressed: () => _showAddAppDialog(app, usageProvider),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: const Text('Add'),
    );
  }

  Widget _buildMonitoredActions(InstalledApp app, UsageProvider usageProvider) {
    final appUsage = usageProvider.monitoredApps[app.packageName];
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Usage Info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            appUsage != null 
                ? '${appUsage.cappedUsagePercentage.toStringAsFixed(0)}%'
                : '0%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        
        // Settings Button
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => _showAppSettingsDialog(app, usageProvider),
        ),
        
        // Remove Button
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => _removeApp(app, usageProvider),
        ),
      ],
    );
  }

  void _showAddAppDialog(InstalledApp app, UsageProvider usageProvider) {
    final timeController = TextEditingController();
    final maxMinutes = 90;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${app.appName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Set daily usage limit for ${app.appName}'),
            const SizedBox(height: 16),
            TextField(
              controller: timeController,
              decoration: InputDecoration(
                labelText: 'Daily Limit (minutes)',
                hintText: 'e.g., 60 for 1 hour',
                helperText: 'Maximum: $maxMinutes minutes',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final minutes = int.tryParse(timeController.text);
              if (minutes != null && minutes > 0 && minutes <= maxMinutes) {
                usageProvider.addAppToMonitoring(
                  app,
                  Duration(minutes: minutes),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${app.appName} added to monitoring'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else if (minutes != null && minutes > maxMinutes) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Maximum daily limit is $maxMinutes minutes'),
                    backgroundColor: Colors.red,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid time between 1 and 90 minutes'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAppSettingsDialog(InstalledApp app, UsageProvider usageProvider) {
    final appUsage = usageProvider.monitoredApps[app.packageName];
    if (appUsage == null) return;
    
    final timeController = TextEditingController(
      text: appUsage.dailyLimit.inMinutes.toString(),
    );
    final maxMinutes = 90;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Settings for ${app.appName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current daily limit: ${appUsage.dailyLimit.inMinutes} minutes'),
            const SizedBox(height: 16),
            TextField(
              controller: timeController,
              decoration: InputDecoration(
                labelText: 'New Daily Limit (minutes)',
                helperText: 'Maximum: $maxMinutes minutes',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final minutes = int.tryParse(timeController.text);
              if (minutes != null && minutes > 0 && minutes <= maxMinutes) {
                usageProvider.updateAppLimit(
                  app.packageName,
                  Duration(minutes: minutes),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${app.appName} limit updated'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else if (minutes != null && minutes > maxMinutes) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Maximum daily limit is $maxMinutes minutes'),
                    backgroundColor: Colors.red,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid time between 1 and 90 minutes'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _removeApp(InstalledApp app, UsageProvider usageProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${app.appName}?'),
        content: const Text('This will stop monitoring this app and remove it from your dashboard.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              usageProvider.removeAppFromMonitoring(app.packageName);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${app.appName} removed from monitoring'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
