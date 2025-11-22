# Gemini AI Integration Guide

## Overview
The WatchTower app has been integrated with Google Gemini API to power two AI agents: **Ade** and **Chidinma**. Each agent has a distinct personality and specialization to support users on their digital wellness journey.

## Agents Overview

### Ade - Mental Health Companion
- **Personality**: Warm, empathetic, and encouraging
- **Focus**: Emotional support and mental wellness
- **Specialties**:
  - Mental Health Support
  - Stress Management
  - Emotional Wellness
  - Mindfulness
- **Greeting**: "Hello! I'm Ade, your mental health companion. I'm here to support you on your wellness journey. How are you feeling today?"

### Chidinma - Digital Wellness Coach
- **Personality**: Motivational, practical, and goal-oriented
- **Focus**: Digital habits and productivity optimization
- **Specialties**:
  - Digital Wellness
  - Productivity Tips
  - Time Management
  - Healthy Tech Habits
- **Greeting**: "Hi there! I'm Chidinma, your digital wellness coach. I'm here to help you build healthier relationships with technology. What would you like to work on today?"

## Technical Integration

### API Configuration
- **Provider**: Google Generative AI
- **Model**: `gemini-1.5-flash` (optimized for speed and cost-effectiveness)
- **API Key**: Configured in `lib/services/gemini_service.dart`

### Key Files Modified

#### 1. `pubspec.yaml`
Added the Google Generative AI package:
```yaml
dependencies:
  google_generative_ai: ^0.4.8
```

#### 2. `lib/services/gemini_service.dart` (NEW)
Core service for Gemini API integration with personality-based prompting:
- `generateResponse()`: Main method to get AI responses
- Personality-based system prompts for each agent
- Fallback responses if API fails
- Conversation history management

#### 3. `lib/screens/main/chat_screen.dart`
Updated to use Gemini service:
- Added `_geminiService` instance
- Added `_isLoading` state for async operations
- Modified `_sendMessage()` to make async API calls
- Disabled input while waiting for response
- Shows loading spinner in send button
- Removed mock response generation

## How It Works

### Chat Flow
1. User types a message and presses send
2. User message is added to the chat
3. Placeholder AI response appears
4. `_sendMessage()` calls `_geminiService.generateResponse()`
5. Gemini API returns personality-matched response
6. Placeholder is replaced with actual response
7. Chat scrolls to bottom

### Personality Matching
Each agent receives a detailed system prompt that includes:
- Agent name and role
- Personality description
- Specialized guidelines for responses
- List of specialties
- Response style expectations

### Conversation Context
The system maintains conversation history by:
- Passing all previous messages to Gemini
- Converting messages to proper role format ('user' or 'model')
- Allowing Gemini to understand context and provide coherent responses

## Example Usage

```dart
final geminiService = GeminiService();

// Get a response from Ade
final response = await geminiService.generateResponse(
  userMessage: "I'm feeling stressed about my phone usage",
  agentName: "Ade",
  agentPersonality: "Warm, empathetic, and encouraging...",
  conversationHistory: previousMessages,
);

// Get a response from Chidinma
final response = await geminiService.generateResponse(
  userMessage: "How can I improve my digital habits?",
  agentName: "Chidinma",
  agentPersonality: "Motivational, practical, and goal-oriented...",
  conversationHistory: previousMessages,
);
```

## Error Handling

- If the API call fails, the service returns a personality-appropriate default response
- User sees a snackbar notification if an error occurs
- Input remains enabled so the user can retry
- All errors are logged for debugging

## Configuration

### To Change the Model
Edit `lib/services/gemini_service.dart`:
```dart
_model = GenerativeModel(
  model: 'gemini-1.5-pro',  // Change here
  apiKey: _apiKey,
);
```

Available models:
- `gemini-1.5-flash`: Fast and cost-effective (recommended)
- `gemini-1.5-pro`: More capable, higher cost
- `gemini-2.0-flash`: Latest model when available

### To Modify Personality
Edit the system prompts in `_buildSystemPrompt()` method to customize behavior:
```dart
String _buildSystemPrompt(String agentName, String agentPersonality) {
  if (agentName == 'Ade') {
    // Modify Ade's instructions here
  } else if (agentName == 'Chidinma') {
    // Modify Chidinma's instructions here
  }
}
```

## Features

✅ Two distinct AI personalities
✅ Conversation history awareness
✅ Personality-based system prompts
✅ Loading states and error handling
✅ Async/await pattern for smooth UX
✅ Fallback responses on API failure
✅ Input disabled while loading

## Future Enhancements

- [ ] Add agent selection screen
- [ ] Implement message persistence to database
- [ ] Add typing indicators
- [ ] Support for voice messages
- [ ] Custom personality fine-tuning
- [ ] Multi-language support
- [ ] Response streaming for faster perceived performance
- [ ] Session context management for long conversations

## Security Notes

⚠️ **Important**: The API key is currently hardcoded in the service. For production:
1. Move the API key to environment variables
2. Implement backend API proxy to hide the key
3. Use Firebase authentication for API access
4. Add rate limiting to prevent abuse

## Testing the Integration

1. Navigate to the Chat Screen
2. Select an agent (Ade or Chidinma)
3. Type a message related to their specialty
4. Wait for the AI response
5. Continue the conversation to test context awareness

## Troubleshooting

### "Model not found" error
- Ensure you're using a valid model name like `gemini-1.5-flash`
- Check that your API key has access to the model

### No response appears
- Check internet connection
- Verify API key is correct
- Check Firebase/cloud console for usage limits

### Responses are not personality-specific
- Verify the system prompt is being sent correctly
- Check that `agentPersonality` parameter matches the agent name
- Review debug logs in the service

## API Rate Limits

Google Generative AI has the following free tier limits:
- 15 requests per minute (RPM)
- 1,000,000 tokens per day

For production deployment, consider upgrading to a paid plan.

## References

- [Google Generative AI Documentation](https://ai.google.dev)
- [Gemini API Reference](https://ai.google.dev/api)
- [Flutter Integration Guide](https://github.com/google/generative-ai-dart)
