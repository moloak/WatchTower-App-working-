import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PaymentsService {
  PaymentsService._();
  static final PaymentsService _instance = PaymentsService._();
  factory PaymentsService() => _instance;

  // The server base URL should point to your deployed Cloud Function or server
  // e.g. https://us-central1-YOUR_PROJECT.cloudfunctions.net/paystack
  String serverBaseUrl = 'https://your-server.example.com/paystack';

  /// Initialize a Paystack transaction for [email], [amount] in kobo (so multiply Naira by 100)
  /// Returns the authorization_url if successful.
  Future<String> initializeTransaction({required String email, required int amountKobo, required String planId, required String uid}) async {
    final url = Uri.parse('$serverBaseUrl/initialize');
    final resp = await http.post(url, body: json.encode({
      'email': email,
      'amount': amountKobo,
      'planId': planId,
      'uid': uid,
    }), headers: {'Content-Type': 'application/json'});

    if (resp.statusCode != 200) {
      throw Exception('Failed to initialize transaction: ${resp.statusCode} ${resp.body}');
    }

    final data = json.decode(resp.body) as Map<String, dynamic>;
    final authUrl = data['authorization_url'] as String?;
    if (authUrl == null) throw Exception('No authorization_url returned');
    return authUrl;
  }

  Future<bool> verifyTransaction({required String reference}) async {
    final url = Uri.parse('$serverBaseUrl/verify');
    final resp = await http.post(url, body: json.encode({'reference': reference}), headers: {'Content-Type': 'application/json'});
    if (resp.statusCode != 200) {
      throw Exception('Verification failed: ${resp.statusCode} ${resp.body}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    return data['status'] == 'success';
  }

  Future<void> openAuthorizationUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $url');
    }
  }
}
