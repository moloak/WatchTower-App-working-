import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'dart:async';

/// A getter that retrieves the Gemini API key from environment variables.
/// **Security**: The API key is now loaded from the .env file instead of being hardcoded.
/// This is the recommended approach for production applications.
String get _apiKey => dotenv.env['GEMINI_API_KEY'] ?? '';

/// Service for interacting with Google Gemini API
/// Provides personality-based responses for Ade and Chidinma agents
class GeminiService {
  // Cache for GenerativeModel instances to avoid re-creating them on every call.
  // The key is the agent name (e.g., 'Ade', 'Chidinma').
  final Map<String, GenerativeModel> _modelCache = {};

  /// Get AI response based on user message and agent personality
  Future<String> generateResponse({
    required String userMessage,
    required String agentName,
    required String agentPersonality,
    List<GeminiChatMessage> conversationHistory = const [],
  }) async {
    if (_apiKey.startsWith('AIzaSy') && _apiKey.length > 35) {
      debugPrint('GeminiService: Using API Key.');
    } else {
      debugPrint('GeminiService: Invalid or missing API Key. Calls will likely fail.');
      return _getDefaultResponse(agentName, isError: true);
    }

    // Check network connectivity first
    try {
      await InternetAddress.lookup('generativelanguage.googleapis.com').timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('DNS lookup timeout'),
      );
      debugPrint('✓ Network connectivity verified');
    } catch (e) {
      debugPrint('✗ No internet connection or DNS lookup failed: $e');
      return _getDefaultResponse(agentName, isError: true);
    }

    try {
      debugPrint('generateResponse called for agent: $agentName');

      // Get or create a cached model for the agent
      final model = _getOrCreateModel(agentName, agentPersonality);
      debugPrint('Model created/retrieved for $agentName');

      // Build the system prompt for this agent
      final systemPrompt = _buildSystemPrompt(agentName, agentPersonality);
      debugPrint('System prompt built');

      // Build conversation history from the custom GeminiChatMessage list
      final history = conversationHistory.map((msg) {
        // The google_generative_ai package expects specific roles.
        // 'user' maps to 'user', and any other role (like 'ai') maps to 'model'.
        final role = msg.role == 'user' ? 'user' : 'model';
        return Content(role, [TextPart(msg.content)]);
      }).toList();

      debugPrint('History built: ${history.length} messages');

      // Start a chat session with the constructed history
      final chat = model.startChat(history: history);
      debugPrint('Chat session started');

      debugPrint('Building message with system prompt...');

      // Build the full prompt with system instructions
      final fullMessage = '$systemPrompt\n\nUser message: $userMessage';

      debugPrint('Sending request to Gemini API (gemini-2.5-flash)...');

      // Send the new user message and wait for the response
      GenerateContentResponse response;
      try {
        response = await chat.sendMessage(
          Content.text(fullMessage),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException('Gemini API request timed out after 30 seconds');
          },
        );
      } catch (apiError) {
        debugPrint('❌ API call failed immediately: $apiError');
        debugPrint('API Error type: ${apiError.runtimeType}');
        debugPrint('API Error details: ${apiError.toString()}');
        rethrow;
      }

      debugPrint('✓ Received response from Gemini API');

      final responseText = response.text;

      if (responseText == null || responseText.isEmpty) {
        debugPrint('⚠ Empty response from Gemini API - returning fallback');
        return _getDefaultResponse(agentName);
      }

      debugPrint('✓ AI response successful: ${responseText.length} characters');
      return responseText;
    } on SocketException catch (e) {
      debugPrint('✗ SOCKET NETWORK ERROR: ${e.message}');
      debugPrint('Device cannot reach generativelanguage.googleapis.com - Check network connectivity');
      debugPrint('Stack: $e');
      return _getDefaultResponse(agentName, isError: true);
    } catch (e, stackTrace) {
      debugPrint('✗ ERROR GENERATING RESPONSE: $e');
      debugPrint('Exception type: ${e.runtimeType}');
      debugPrint('Full error: ${e.toString()}');
      debugPrint('Stack trace: $stackTrace');
      
      // Check for specific errors
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('api key')) {
        debugPrint('→ Likely cause: Invalid or expired API key');
      } else if (errorStr.contains('permission') || errorStr.contains('forbidden')) {
        debugPrint('→ Likely cause: API key permissions issue');
      } else if (errorStr.contains('network') || errorStr.contains('connection')) {
        debugPrint('→ Likely cause: Network connectivity issue');
      } else if (errorStr.contains('timeout')) {
        debugPrint('→ Likely cause: Request timeout - network is slow');
      }
      
      // Return error fallback
      return _getDefaultResponse(agentName, isError: true);
    }
  }

  /// Retrieves a cached [GenerativeModel] for an agent or creates a new one.
  GenerativeModel _getOrCreateModel(String agentName, String agentPersonality) {
    if (_modelCache.containsKey(agentName)) {
      debugPrint('Returning cached model for $agentName.');
      return _modelCache[agentName]!;
    }

    debugPrint('Creating new model for $agentName.');

    final newModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
    );

    _modelCache[agentName] = newModel;
    return newModel;
  }

  /// Build a system prompt based on agent personality and role
  String _buildSystemPrompt(String agentName, String agentPersonality) {
    if (agentName == 'Ade') {
      return '''You are Ade, a supportive mental health companion. Your personality: $agentPersonality

Guidelines for responses:
- Be warm, empathetic, and encouraging
- Focus on emotional support and mental wellness
- Use compassionate language and validate feelings
- Provide mindfulness and stress management suggestions
- Ask clarifying questions to better understand the user's needs
- Keep responses concise but meaningful (2-3 sentences typically)
- Do not provide medical advice; suggest professional help when appropriate

Your specialties are:
- Mental Health Support
- Stress Management
- Emotional Wellness
- Mindfulness

Always respond as if you're having a caring conversation with someone who trusts you.''';
    } else if (agentName == 'Chidinma') {
      return '''You are Chidinma, a digital wellness and productivity coach. Your personality: $agentPersonality

Guidelines for responses:
- Be motivational, practical, and goal-oriented
- Focus on building healthy digital habits and productivity
- Provide actionable tips and strategies
- Use encouraging language that inspires positive change
- Help break down goals into manageable steps
- Ask what specific challenges the user is facing
- Keep responses concise but practical (2-3 sentences typically)
- Emphasize that digital wellness is about balance, not perfection

Your specialties are:
- Digital Wellness
- Productivity Tips
- Time Management
- Healthy Tech Habits

Always respond as if you're coaching someone toward their digital wellness goals.''';
    }

    return 'You are an AI assistant helping with digital wellness and mental health support.';
  }

  /// Get default fallback response if API fails
  String _getDefaultResponse(String agentName, {bool isError = false}) {
    if (isError) {
      return 'I seem to be having trouble connecting right now. Please try again in a moment.';
    }

    if (agentName == 'Ade') {
      return 'I\'m here for you. Could you tell me a bit more about what you\'re experiencing? I\'d like to better understand how I can support you.';
    } else if (agentName == 'Chidinma') {
      return 'Great question! Let me help you with practical strategies. What specific aspect of your digital wellness would you like to focus on?';
    }
    return 'I\'m here to help. How can I assist you today?';
  }
}

/// Helper class to manage chat message role conversion for Gemini
class GeminiChatMessage {
  final String content;
  final String role; // 'user' or 'model'

  GeminiChatMessage({
    required this.content,
    required this.role,
  });
}
