# Gemini API Configuration

## Active Configuration

**API Key**: `AIzaSyBTiI_wEMxGyIJuXPxH4qo4fTuxOdZ2wV8`
**Model**: `gemini-1.5-flash`
**Location**: `lib/services/gemini_service.dart`

## Model Information

### Gemini 1.5 Flash
- **Type**: Fast, efficient model
- **Use Case**: Real-time applications, cost-sensitive scenarios
- **Speed**: ~500ms typical response time
- **Cost**: Most economical option
- **Capabilities**: Excellent for conversational AI

## Features Enabled

- ✅ Multi-turn conversations
- ✅ System prompts for personality control
- ✅ Conversation history context
- ✅ Streaming responses (supported but not used)
- ✅ Function calling (not currently used)

## API Limits

### Free Tier
- Rate Limit: 15 requests per minute (RPM)
- Daily Limit: 1,000,000 tokens per day
- Cost: Free

### Recommended for Production
- Upgrade to paid tier in Google Cloud Console
- Enable usage alerts
- Set maximum quota limits
- Monitor costs regularly

## Integration Points

### Service Layer
- File: `lib/services/gemini_service.dart`
- Initialization: Lazy loaded on chat screen open
- Connection: HTTP/REST through Google API

### Chat Screen Integration
- File: `lib/screens/main/chat_screen.dart`
- Trigger: User sends message
- Flow: Message → API Call → Response → Display

## Personality Configuration

### System Prompts

Each agent receives a detailed system prompt:

**Ade (Mental Health)**
- Role: Supportive mental health companion
- Style: Warm, empathetic, encouraging
- Guidelines: Emotional validation, mindfulness suggestions
- Tone: Caring and non-judgmental

**Chidinma (Digital Wellness)**
- Role: Productivity and wellness coach
- Style: Motivational, practical, goal-oriented
- Guidelines: Actionable strategies, habit formation
- Tone: Encouraging and supportive

## Conversation Management

### Message Format
```dart
// User message
role: 'user'
content: "User's question or statement"

// AI response
role: 'model'
content: "AI's personality-matched response"
```

### Context Window
- Passes full conversation history
- Allows coherent multi-turn conversations
- Maintains context across messages
- Natural conversational flow

## Error Handling

### API Errors
- Rate limit exceeded → Shows user message, can retry
- Model not found → Uses fallback response
- Network error → Shows snackbar notification
- Invalid API key → Returns default response

### Fallback Responses

**Ade's Fallback:**
"I'm here for you. Could you tell me a bit more about what you're experiencing? I'd like to better understand how I can support you."

**Chidinma's Fallback:**
"Great question! Let me help you with practical strategies. What specific aspect of your digital wellness would you like to focus on?"

## Monitoring & Debugging

### Logs
- Located in Flutter debug console
- Errors prefixed with "Error in GeminiService"
- Responses logged with agent name and timestamp

### Debug Info
```dart
// Enable debug logging
debugPrint('GeminiService: Sending request for $agentName');
debugPrint('Response received: $responseText');
```

## Security Best Practices

### Current Implementation
⚠️ API key hardcoded for development purposes only

### Production Recommendations

1. **Environment Variables**
   ```
   GEMINI_API_KEY=your_key_here
   GEMINI_MODEL=gemini-1.5-flash
   ```

2. **Backend Proxy Pattern**
   - Frontend → Your Backend → Google API
   - Backend validates and forwards requests
   - Protects API key from client exposure

3. **Authentication**
   - Use Firebase Authentication
   - Associate API calls with user accounts
   - Track usage per user

4. **Rate Limiting**
   - Implement per-user rate limits
   - Prevent abuse and costs
   - Monitor suspicious patterns

5. **Cost Control**
   - Set daily spending limits in Cloud Console
   - Monitor API usage dashboard
   - Set up billing alerts

## Testing the Integration

### Quick Test
```bash
cd c:\users\hello\desktop\WatchTower-App-working-
flutter pub get
flutter run
```

### Manual Testing
1. Open app
2. Go to Chat Screen
3. Select agent (Ade or Chidinma)
4. Send test message
5. Verify personality-matched response

### Integration Tests
- Test fallback response on network error
- Test long conversation context
- Test rapid message sends (rate limiting)
- Test both agent personalities

## Upgrading to Production

### Step 1: Get API Key
- Visit [Google AI Studio](https://aistudio.google.com)
- Create new project
- Generate API key
- Add to environment variables

### Step 2: Update Configuration
```dart
// Instead of hardcoded key:
static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
```

### Step 3: Backend Implementation (Optional)
Create endpoint: `POST /api/chat/generate`
- Validates user session
- Forwards to Gemini API
- Returns response to client

### Step 4: Deploy
- Update environment variables on hosting platform
- Test in staging environment
- Monitor logs and metrics
- Deploy to production

## Cost Estimation

### Example Usage Patterns

**Light Use** (10 messages/day)
- ~5,000 tokens/day
- Cost: ~$0.015/day (~$0.45/month)

**Medium Use** (50 messages/day)
- ~25,000 tokens/day
- Cost: ~$0.075/day (~$2.25/month)

**Heavy Use** (200 messages/day)
- ~100,000 tokens/day
- Cost: ~$0.30/day (~$9/month)

Note: Prices based on gemini-1.5-flash rates (as of Nov 2024)

## Troubleshooting

### Model Not Found Error
```
Error: models/gemini-1.5-flash is not found for API version v1beta
```
**Solution**: Verify model name is correct in GeminiService.dart

### Rate Limit Error
```
Error: Quota exceeded for quota metric 'Read requests'
```
**Solution**: Wait before retrying, or upgrade to paid tier

### Invalid API Key
```
Error: API key not valid. Please pass a valid API key
```
**Solution**: Check API key in GeminiService.dart, regenerate if needed

### Network Timeout
```
Error: The request to the API server was not completed before the timeout.
```
**Solution**: Check internet connection, increase timeout if needed

## Resources

- [Google Generative AI Docs](https://ai.google.dev)
- [Gemini API Reference](https://ai.google.dev/api)
- [Flutter Integration Guide](https://github.com/google/generative-ai-dart)
- [Pricing & Limits](https://ai.google.dev/pricing)
