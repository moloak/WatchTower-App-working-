# Quick Start Guide - Gemini Integration Testing

## Prerequisites

- Flutter SDK installed
- Android device or emulator
- Internet connection
- Visual Studio Code with Flutter extension

## Step 1: Install Dependencies

```bash
cd c:\users\hello\desktop\WatchTower-App-working-
flutter pub get
```

Expected output:
```
Got dependencies!
55 packages have newer versions incompatible with dependency constraints.
```

## Step 2: Build the App

```bash
flutter run
```

Or for a specific device:
```bash
flutter run -d <device_id>
```

## Step 3: Navigate to Chat

1. Open the app
2. Tap on the Chat tab in bottom navigation
3. Wait for chat screen to load

## Step 4: Test Ade (Mental Health Agent)

### Message 1: Basic greeting
Send: "Hello"
Expected: Warm greeting about mental health support

### Message 2: Stress topic
Send: "I'm feeling stressed about my phone usage"
Expected: Empathetic response with mindfulness suggestions

### Message 3: Follow-up
Send: "Can you suggest a quick mindfulness exercise?"
Expected: Practical mindfulness technique

## Step 5: Test Chidinma (Digital Wellness Agent)

### Message 1: Basic greeting
Send: "Hi"
Expected: Motivational greeting about digital wellness

### Message 2: Productivity topic
Send: "How can I improve my digital productivity?"
Expected: Practical, goal-oriented strategies

### Message 3: Action steps
Send: "What's the first step I should take?"
Expected: Specific, achievable first steps

## Step 6: Test Context Awareness

Send multiple related messages in sequence:
1. "I use TikTok too much"
2. "It wastes about 2 hours daily"
3. "What should I do about it?"

Verify: Responses show understanding of previous context

## Expected Behaviors

✅ **Loading Spinner**: Send button shows spinner while waiting
✅ **Disabled Input**: Cannot type while API is responding
✅ **Message Bubbles**: User messages on right (blue), AI on left (gray)
✅ **Timestamps**: Each message shows "Just now" or time elapsed
✅ **Auto Scroll**: Chat scrolls to latest message
✅ **Error Messages**: Snackbar appears if API fails

## Troubleshooting

### No response appears
1. Check internet connection
2. Look for error in debug console
3. Try again after a few seconds

### Error: "Model not found"
- API key or model name is incorrect
- Check GEMINI_API_CONFIG.md for correct settings

### "Rate limit exceeded" error
- Wait 60 seconds before sending another message
- Or upgrade to paid Google API tier

### Build fails
Run: `flutter clean && flutter pub get && flutter run`

### Debug Output
View real-time logs:
```bash
flutter logs
```

Filter for Gemini:
```bash
flutter logs | grep -i gemini
```

## Testing Both Agents Simultaneously

If testing on multiple devices:

**Device 1**: Test Ade (Mental Health)
**Device 2**: Test Chidinma (Digital Wellness)

Or test in sequence on same device:
1. Test Ade with several messages
2. Switch to Chidinma (if agent selection implemented)
3. Test Chidinma with several messages

## Load Testing

To test API stability, send rapid messages:
```
1. "Hello"
2. "How are you?"
3. "Tell me more"
4. "Another question"
5. "Final message"
```

Monitor:
- Response times
- Loading state accuracy
- No crashes or freezes

## Check Conversation History

The chat maintains full conversation history. To verify:
1. Send 3-4 related messages
2. Look at each response
3. Verify agent remembers previous context

Example conversation flow:
```
User: "I have a phone addiction"
→ Agent asks clarifying questions

User: "Social media, especially Instagram"
→ Agent references Instagram specifically

User: "I spend 4 hours daily"
→ Agent knows the amount from context
```

## Verify Personality Differences

### Test Ade
Send: "I'm having a bad day"
- Listen for: Empathy, emotional validation, comfort

### Test Chidinma
Send: "I'm having a bad day"
- Listen for: Motivation, action steps, practical solutions

## Performance Metrics to Note

- **Cold start response**: First message (longer)
- **Warm response**: Subsequent messages (faster)
- **Average response time**: ~500-2000ms
- **Text generation speed**: ~100-200 words/5 seconds

## What to Look For

1. ✅ Personality consistency (Ade is warm, Chidinma is practical)
2. ✅ Context awareness (remembers previous messages)
3. ✅ Relevant responses (answers the actual question)
4. ✅ Appropriate length (2-3 sentences typically)
5. ✅ No technical jargon (friendly, accessible language)
6. ✅ Encouragement (both agents supportive)

## Common Test Cases

### Mental Health (Ade)
- "I'm anxious about my screen time"
- "How do I practice mindfulness?"
- "I feel guilty about my app usage"

### Digital Wellness (Chidinma)
- "I want to reduce my phone time"
- "How do I set healthy tech habits?"
- "What's a realistic time limit?"

### Context Awareness (Both)
- "I told you I use Instagram"
- "Remember I said I spend 4 hours?"
- "Based on what I mentioned..."

## Debugging Tips

### Enable verbose logging
```bash
flutter run -v
```

### Check API response
Add this to `gemini_service.dart`:
```dart
debugPrint('Response: ${response.text}');
```

### Monitor token usage
Response includes token count in headers (visible in logs)

### Test fallback responses
Disconnect internet to trigger fallback:
```dart
// Both agents will return their default responses
```

## Session Management

- Each chat session is independent
- Conversation history resets when app restarts
- Sessions are not persisted (development version)

## Next Steps After Testing

1. ✅ Verify both agents work
2. ✅ Check personality consistency
3. ✅ Confirm error handling
4. ✅ Test on actual device (not just emulator)
5. ✅ Monitor API usage in Google Cloud Console
6. → Ready for production deployment

## Getting Help

If you encounter issues:
1. Check `GEMINI_API_CONFIG.md` for API settings
2. Review `GEMINI_INTEGRATION.md` for technical details
3. Check debug logs: `flutter logs | grep -i error`
4. Verify internet connection
5. Try `flutter clean && flutter pub get`

## Success Indicators

🎉 **All tests pass when you see:**
- ✅ AI responses appear within 2-3 seconds
- ✅ Both agents have distinct personalities
- ✅ Context is maintained across messages
- ✅ No errors in debug console
- ✅ UI remains responsive during API calls
- ✅ Loading states work correctly

You're ready to deploy! 🚀
