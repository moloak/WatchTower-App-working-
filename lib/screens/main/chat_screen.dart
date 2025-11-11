import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/chat_model.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ChatSession? _currentSession;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final user = userProvider.user;
      
      if (user != null) {
        // Create or get existing chat session
        final existingSessions = userProvider.getChatSessionsByCategory(ChatCategory.general);
        if (existingSessions.isNotEmpty) {
          _currentSession = existingSessions.first;
        } else {
          _createNewSession(userProvider, user.selectedAiAgent);
        }
      }
    });
  }

  void _createNewSession(UserProvider userProvider, String aiAgent) {
    final session = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: userProvider.user!.id,
      aiAgentName: aiAgent,
      messages: [
        ChatMessage(
          id: '1',
          content: _getGreetingMessage(aiAgent),
          timestamp: DateTime.now(),
          type: MessageType.ai,
          aiAgentName: aiAgent,
        ),
      ],
      createdAt: DateTime.now(),
      lastActivity: DateTime.now(),
      title: 'Chat with $aiAgent',
      category: ChatCategory.general,
    );
    
    userProvider.addChatSession(session);
    _currentSession = session;
  }

  String _getGreetingMessage(String aiAgent) {
    if (aiAgent == 'Ade') {
      return AiAgent.ade.greeting;
    } else {
      return AiAgent.shalewa.greeting;
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentSession == null) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    
    // Add user message
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      timestamp: DateTime.now(),
      type: MessageType.user,
    );

    // Add AI response (mock for now)
    final aiResponse = ChatMessage(
      id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
      content: _generateAiResponse(text, _currentSession!.aiAgentName),
      timestamp: DateTime.now(),
      type: MessageType.ai,
      aiAgentName: _currentSession!.aiAgentName,
    );

    final updatedMessages = [..._currentSession!.messages, userMessage, aiResponse];
    final updatedSession = _currentSession!.copyWith(
      messages: updatedMessages,
      lastActivity: DateTime.now(),
    );

    userProvider.updateChatSession(updatedSession);
    _currentSession = updatedSession;
    
    _messageController.clear();
    
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _generateAiResponse(String userMessage, String aiAgent) {
    // Mock AI responses - in real implementation, this would call an AI API
    final responses = {
      'Ade': [
        "I understand how you're feeling. Let's work through this together.",
        "That sounds challenging. Remember, it's okay to take breaks and prioritize your mental health.",
        "I'm here to support you. What specific aspect of your digital wellness would you like to focus on?",
        "It's great that you're being mindful about your technology use. Small changes can make a big difference.",
        "Let's explore some mindfulness techniques that might help you feel more balanced.",
      ],
      'Chidinma': [
        "Great question! Let me help you optimize your digital habits for better productivity.",
        "I can see you're committed to improving your digital wellness. Here are some strategies that might help.",
        "Let's break down your goals into manageable steps. What's your biggest challenge right now?",
        "I recommend setting specific, achievable goals for your app usage. Would you like to start with one app?",
        "Remember, digital wellness is about balance, not perfection. Let's find what works for you.",
      ],
    };

    final agentResponses = responses[aiAgent] ?? responses['Ade']!;
    return agentResponses[DateTime.now().millisecond % agentResponses.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<UserProvider>(
          builder: (context, userProvider, child) {
            final user = userProvider.user;
            if (user == null) return const Text('Chat');
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chat with ${user.selectedAiAgent}'),
                Text(
                  'Your ${user.selectedAiAgent == 'Ade' ? 'Mental Health' : 'Digital Wellness'} Coach',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAiAgentInfo,
          ),
        ],
      ),
      body: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          if (_currentSession == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          return Column(
            children: [
              // Chat Messages
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _currentSession!.messages.length,
                  itemBuilder: (context, index) {
                    final message = _currentSession!.messages[index];
                    return _buildMessageBubble(message);
                  },
                ),
              ),
              
              // Message Input
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outline.withAlpha((0.2 * 255).round()),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      onPressed: _sendMessage,
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.type == MessageType.user;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                message.aiAgentName?.substring(0, 1) ?? 'A',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                  bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                ),
                border: !isUser ? Border.all(
                  color: Theme.of(context).colorScheme.outline.withAlpha((0.2 * 255).round()),
                ) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: isUser 
                          ? Colors.white.withAlpha((0.7 * 255).round())
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.secondary,
              child: const Icon(
                Icons.person,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  void _showAiAgentInfo() {
    final user = Provider.of<UserProvider>(context, listen: false).user;
    if (user == null) return;
    
    final agent = user.selectedAiAgent == 'Ade' ? AiAgent.ade : AiAgent.shalewa;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('About ${agent.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              agent.description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Specialties:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...agent.specialties.map((specialty) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(specialty),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

