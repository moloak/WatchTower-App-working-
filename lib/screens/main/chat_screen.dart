import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../models/chat_model.dart';
import '../../services/gemini_service.dart' as gemini;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ChatSession? _currentSession;
  final gemini.GeminiService _geminiService = gemini.GeminiService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Chat initialization moved to build method for proper timing
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    setState(() {
      _currentSession = session;
    });
  }

  String _getGreetingMessage(String aiAgent) {
    if (aiAgent == 'Ade') {
      return AiAgent.ade.greeting;
    } else if (aiAgent == 'Chidinma') {
      return AiAgent.shalewa.greeting;
    } else {
      return AiAgent.ade.greeting;
    }
  }

  void _sendMessage() async {
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

    // Add placeholder AI message that will be updated
    final placeholderId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    final placeholderResponse = ChatMessage(
      id: placeholderId,
      content: '...',
      timestamp: DateTime.now(),
      type: MessageType.ai,
      aiAgentName: _currentSession!.aiAgentName,
    );

    // Update UI with user message and placeholder
    var updatedMessages = [..._currentSession!.messages, userMessage, placeholderResponse];
    var updatedSession = _currentSession!.copyWith(
      messages: updatedMessages,
      lastActivity: DateTime.now(),
    );

    // Don't update the provider yet - we'll do it after we get the response
    // Just update the local state for UI purposes
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

    // Set loading state
    setState(() {
      _isLoading = true;
    });

    try {
      // Get agent personality
      final agent = _currentSession!.aiAgentName == 'Ade' 
          ? AiAgent.ade 
          : AiAgent.shalewa;

      // Convert chat history to Gemini format
      // Build history from all previous messages (excluding the user message just sent)
      // The history should be: greeting (skip), user1, model1, user2, model2, etc.
      final historyMessages = _currentSession!.messages
          .take(_currentSession!.messages.length - 1) // Exclude the placeholder AI response we just added
          .toList();
      
      // Skip the greeting message (first message)
      final messageHistory = historyMessages.isNotEmpty ? historyMessages.skip(1).toList() : [];
      
      final conversationHistory = messageHistory
          .map((msg) => gemini.GeminiChatMessage(
                content: msg.content,
                role: msg.type == MessageType.user ? 'user' : 'model',
              ))
          .toList();

      debugPrint('ChatScreen: Calling generateResponse. History: ${conversationHistory.length} messages');
      
      // Get AI response from Gemini
      final aiResponseText = await _geminiService.generateResponse(
        userMessage: text,
        agentName: _currentSession!.aiAgentName,
        agentPersonality: agent.personality,
        conversationHistory: conversationHistory,
      );
      
      debugPrint('ChatScreen: Got response from Gemini');

      // Create actual AI response
      final aiResponse = ChatMessage(
        id: placeholderId,
        content: aiResponseText,
        timestamp: DateTime.now(),
        type: MessageType.ai,
        aiAgentName: _currentSession!.aiAgentName,
      );

      // Update with actual response - rebuild from scratch with all previous messages
      final finalMessages = [
        ..._currentSession!.messages.where((msg) => msg.id != userMessage.id && msg.id != placeholderId),
        userMessage,
        aiResponse,
      ];
      
      final finalSession = _currentSession!.copyWith(
        messages: finalMessages,
        lastActivity: DateTime.now(),
      );

      if (mounted) {
        userProvider.updateChatSession(finalSession);
        _currentSession = finalSession;

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

        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error getting AI response: $e');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
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
          // If user is not loaded, show loading
          if (userProvider.user == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // Initialize session if not yet done
          if (_currentSession == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final existingSessions = userProvider.getChatSessionsByCategory(ChatCategory.general);
              if (existingSessions.isNotEmpty) {
                setState(() {
                  _currentSession = existingSessions.first;
                });
              } else {
                _createNewSession(userProvider, userProvider.user!.selectedAiAgent);
              }
            });
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
                        enabled: !_isLoading,
                        decoration: InputDecoration(
                          hintText: _isLoading ? 'Waiting for response...' : 'Type your message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        onSubmitted: (_) => _isLoading ? null : _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      onPressed: _isLoading ? null : _sendMessage,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
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

