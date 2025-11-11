class ChatMessage {
  final String id;
  final String content;
  final DateTime timestamp;
  final MessageType type;
  final String? senderId;
  final String? aiAgentName;

  ChatMessage({
    required this.id,
    required this.content,
    required this.timestamp,
    required this.type,
    this.senderId,
    this.aiAgentName,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString(),
      'senderId': senderId,
      'aiAgentName': aiAgentName,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
      type: MessageType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => MessageType.user,
      ),
      senderId: json['senderId'],
      aiAgentName: json['aiAgentName'],
    );
  }
}

enum MessageType {
  user,
  ai,
  system,
}

class ChatSession {
  final String id;
  final String userId;
  final String aiAgentName;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime lastActivity;
  final String? title;
  final ChatCategory category;

  ChatSession({
    required this.id,
    required this.userId,
    required this.aiAgentName,
    required this.messages,
    required this.createdAt,
    required this.lastActivity,
    this.title,
    this.category = ChatCategory.general,
  });

  ChatSession copyWith({
    String? id,
    String? userId,
    String? aiAgentName,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? lastActivity,
    String? title,
    ChatCategory? category,
  }) {
    return ChatSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      aiAgentName: aiAgentName ?? this.aiAgentName,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      lastActivity: lastActivity ?? this.lastActivity,
      title: title ?? this.title,
      category: category ?? this.category,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'aiAgentName': aiAgentName,
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'lastActivity': lastActivity.toIso8601String(),
      'title': title,
      'category': category.toString(),
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'],
      userId: json['userId'],
      aiAgentName: json['aiAgentName'],
      messages: (json['messages'] as List)
          .map((m) => ChatMessage.fromJson(m))
          .toList(),
      createdAt: DateTime.parse(json['createdAt']),
      lastActivity: DateTime.parse(json['lastActivity']),
      title: json['title'],
      category: ChatCategory.values.firstWhere(
        (e) => e.toString() == json['category'],
        orElse: () => ChatCategory.general,
      ),
    );
  }
}

enum ChatCategory {
  general,
  mentalHealth,
  digitalWellness,
  usageTips,
  stressManagement,
  productivity,
}

class AiAgent {
  final String name;
  final String description;
  final String personality;
  final String avatar;
  final List<String> specialties;
  final String greeting;

  const AiAgent({
    required this.name,
    required this.description,
    required this.personality,
    required this.avatar,
    required this.specialties,
    required this.greeting,
  });

  static const ade = AiAgent(
    name: 'Ade',
    description: 'Your supportive mental health companion',
    personality: 'Warm, empathetic, and encouraging. Ade focuses on emotional support and mental wellness.',
    avatar: 'assets/avatars/ade.png',
    specialties: [
      'Mental Health Support',
      'Stress Management',
      'Emotional Wellness',
      'Mindfulness',
    ],
    greeting: 'Hello! I\'m Ade, your mental health companion. I\'m here to support you on your wellness journey. How are you feeling today?',
  );

  static const shalewa = AiAgent(
    name: 'Chidinma',
    description: 'Your digital wellness and productivity coach',
    personality: 'Motivational, practical, and goal-oriented. Chidinma helps with digital habits and productivity.',
    avatar: 'assets/avatars/shalewa.png',
    specialties: [
      'Digital Wellness',
      'Productivity Tips',
      'Time Management',
      'Healthy Tech Habits',
    ],
    greeting: 'Hi there! I\'m Chidinma, your digital wellness coach. I\'m here to help you build healthier relationships with technology. What would you like to work on today?',
  );

  static const List<AiAgent> availableAgents = [ade, shalewa];
}

