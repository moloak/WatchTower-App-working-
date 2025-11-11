import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/payments_service.dart';
import '../../providers/user_provider.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _loading = false;
  String? _selectedPlan; // 'monthly' or 'yearly'

  @override
  Widget build(BuildContext context) {
    final userProv = Provider.of<UserProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a plan')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Plans', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // Monthly plan card
            GestureDetector(
              onTap: () => setState(() => _selectedPlan = 'monthly'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _selectedPlan == 'monthly' ? Colors.orange.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _selectedPlan == 'monthly' ? Colors.orange : Colors.grey.shade200, width: 2),
                  boxShadow: _selectedPlan == 'monthly'
                      ? [BoxShadow(color: Colors.orange.withOpacity(0.08), blurRadius: 12, offset: const Offset(0,6))]
                      : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0,2))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Monthly', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 6),
                          Text('₦5,000 / month', style: TextStyle(fontSize: 16, color: Colors.black87)),
                        ],
                      ),
                    ),
                    Radio<String>(
                      value: 'monthly',
                      groupValue: _selectedPlan,
                      onChanged: (v) => setState(() => _selectedPlan = v),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Yearly plan card (recommended)
            GestureDetector(
              onTap: () => setState(() => _selectedPlan = 'yearly'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _selectedPlan == 'yearly' ? Colors.orange.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _selectedPlan == 'yearly' ? Colors.orange : Colors.grey.shade200, width: 2),
                  boxShadow: _selectedPlan == 'yearly'
                      ? [BoxShadow(color: Colors.orange.withOpacity(0.08), blurRadius: 12, offset: const Offset(0,6))]
                      : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0,2))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Yearly', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('Recommended', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text('₦55,000 / year', style: TextStyle(fontSize: 16, color: Colors.black87)),
                          const SizedBox(height: 6),
                          const Text('Save money with annual billing', style: TextStyle(fontSize: 13, color: Colors.black54)),
                        ],
                      ),
                    ),
                    Radio<String>(
                      value: 'yearly',
                      groupValue: _selectedPlan,
                      onChanged: (v) => setState(() => _selectedPlan = v),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _selectedPlan == null || _loading ? null : () => _startCheckout(userProv, context),
              child: _loading ? const SizedBox(height:18,width:18,child:CircularProgressIndicator.adaptive(strokeWidth:2)) : const Text('Continue to payment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planTile(String id, String title, String subtitle, String desc) {
    final selected = _selectedPlan == id;
    return ListTile(
      selected: selected,
      tileColor: selected ? Colors.orange.shade50 : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: () => setState(() => _selectedPlan = id),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check_circle, color: Colors.orange) : null,
    );
  }

  Future<void> _startCheckout(UserProvider userProv, BuildContext ctx) async {
    if (_selectedPlan == null) return;
    setState(() => _loading = true);
    try {
      // Capture necessary values before awaiting
      final email = userProv.user?.email ?? '';
      final uid = userProv.user?.id ?? '';
      final amountKobo = _selectedPlan == 'monthly' ? 5000 * 100 : 55000 * 100;
      final planId = _selectedPlan!;

      final authUrl = await PaymentsService().initializeTransaction(email: email, amountKobo: amountKobo, planId: planId, uid: uid);
      await PaymentsService().openAuthorizationUrl(authUrl);

      // Ensure the widget is still mounted before showing dialogs
      if (!mounted) return;

      final result = await showDialog<bool>(context: ctx, builder: (dctx) {
        return AlertDialog(
          title: const Text('Complete payment'),
          content: const Text('After completing payment in the browser, tap the button below to verify and activate your subscription.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Not yet')),
            ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('I paid')),
          ],
        );
      });

      if (!mounted) return;

      if (result == true) {
        // Ask user for transaction reference
        final ref = await _askForReference();
        if (!mounted) return;
        if (ref != null && ref.isNotEmpty) {
          // verify via UserProvider helper
          await userProv.verifyPaymentAndActivate(ref);
          if (!mounted) return;
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Verification requested. Subscription will be activated if payment is valid.')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Payment error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askForReference() async {
    String? value;
    await showDialog<void>(context: context, builder: (ctx) {
      final ctrl = TextEditingController();
      return AlertDialog(
        title: const Text('Enter transaction reference'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reference')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () { value = ctrl.text.trim(); Navigator.of(ctx).pop(); }, child: const Text('Verify')),
        ],
      );
    });
    return value;
  }
}
