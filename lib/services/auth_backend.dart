import 'dart:convert';
import 'package:http/http.dart' as http;

// Replace this with your deployed Cloud Function / server endpoint URL.
// Example: https://us-central1-yourproject.cloudfunctions.net/createPasswordResetLink
const String kAuthBackendEndpoint = 'REPLACE_WITH_YOUR_FUNCTION_URL';

/// Calls the backend endpoint to request a password reset for [email].
/// Returns a map with:
/// - canReset: bool (whether client should proceed with reset)
/// - reason: optional string (e.g., 'google')
/// - sent: optional bool (whether server sent the email)
/// - resetLink: optional string (server-generated link)
/// On network or server failure this will throw.
Future<Map<String, dynamic>> requestPasswordReset(String email) async {
  if (kAuthBackendEndpoint == 'REPLACE_WITH_YOUR_FUNCTION_URL') {
    throw StateError('Auth backend endpoint is not configured. Set kAuthBackendEndpoint in auth_backend.dart');
  }

  final uri = Uri.parse(kAuthBackendEndpoint);
  final resp = await http
      .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email}))
      .timeout(const Duration(seconds: 10));

  if (resp.statusCode != 200) {
    throw Exception('Auth backend returned ${resp.statusCode}: ${resp.body}');
  }

  final body = jsonDecode(resp.body) as Map<String, dynamic>;
  return body;
}
