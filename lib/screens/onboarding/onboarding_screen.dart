import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state_provider.dart';
import '../../models/chat_model.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  String _selectedAiAgent = 'Ade';

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Watchtower App',
      subtitle: 'Your Digital Wellness Guardian',
      description: 'Take control of your digital habits and build a healthier relationship with technology.',
      icon: Icons.security,
      // Use theme primary for onboarding accents; specific page color still available
      color: Colors.transparent,
    ),
    OnboardingPage(
      title: 'Monitor App Usage',
      subtitle: 'Track Your Digital Time',
      description: 'Set daily limits for your apps and get notified when you\'re approaching your limits.',
      icon: Icons.analytics,
      color: Colors.transparent,
    ),
    OnboardingPage(
      title: 'Smart Notifications',
      subtitle: 'Stay in Control',
      description: 'Receive gentle reminders at 30%, 60%, and 90% of your daily limits.',
      icon: Icons.notifications_active,
      color: const Color(0xFF06B6D4),
    ),
    OnboardingPage(
      title: 'AI Wellness Coach',
      subtitle: 'Choose Your Companion',
      description: 'Get personalized support from Ade (mental health) or Chidinma (digital wellness).',
      icon: Icons.psychology,
      color: const Color(0xFF10B981),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _completeOnboarding() {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    appState.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pageViewHeight = constraints.maxHeight * 0.60;

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Progress Indicator
                    Container(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: (_currentPage + 1) / _pages.length,
                              backgroundColor: Colors.grey.withAlpha((0.3 * 255).round()),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '${_currentPage + 1}/${_pages.length}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                          // Show an X (skip) button on the first onboarding page so users
                          // can bypass the rest of onboarding.
                          if (_currentPage == 0) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Skip onboarding',
                              onPressed: _completeOnboarding,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Page Content (fixed fraction of available height)
                    SizedBox(
                      height: pageViewHeight,
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            _currentPage = index;
                          });
                        },
                        itemCount: _pages.length,
                        itemBuilder: (context, index) {
                          final page = _pages[index];
                          return _buildPageContent(page);
                        },
                      ),
                    ),

                    // AI Agent Selection (only on last page)
                    if (_currentPage == _pages.length - 1)
                      _buildAiAgentSelection(),

                    // Navigation Buttons
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          if (_currentPage > 0)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _previousPage,
                                child: const Text('Back'),
                              ),
                            ),
                          if (_currentPage > 0) const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _nextPage,
                              child: Text(_currentPage == _pages.length - 1 ? 'Get Started' : 'Next'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPageContent(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withAlpha((0.12 * 255).round()),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              page.icon,
              size: 60,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Title
          Text(
            page.title,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 16),
          
          // Subtitle
          Text(
            page.subtitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 24),
          
          // Description
          Text(
            page.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.grey[600],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAiAgentSelection() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withAlpha((0.2 * 255).round()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Your AI Wellness Coach',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Ade Option
          _buildAiAgentOption(
            agent: AiAgent.ade,
            isSelected: _selectedAiAgent == 'Ade',
            onTap: () => setState(() => _selectedAiAgent = 'Ade'),
          ),
          
          const SizedBox(height: 12),
          
          // Chidinma Option
          _buildAiAgentOption(
            agent: AiAgent.shalewa,
            isSelected: _selectedAiAgent == 'Chidinma',
            onTap: () => setState(() => _selectedAiAgent = 'Chidinma'),
          ),
        ],
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

class OnboardingPage {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;

  OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
  });
}

