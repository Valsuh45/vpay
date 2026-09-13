/// A runnable example, pointed at `compose.demo.yml`
/// (docs/plans/2026-09-13-flutter-plugin-brief.md, Lane A).
///
/// **This example cannot open a window.** No platform host exists in this
/// repository yet (Lane C) — `VpayCheckout.start` reaches
/// `VpayCheckoutPlatform.instance` (the `UnimplementedVpayCheckoutPlatform`
/// stub) and throws `UnimplementedError`, on purpose: see
/// `docs/sdks/parity.md`'s dated ⛔ row for this package. This app still
/// exercises the pre-flight (a real `GET
/// /v1/browser/checkout/sessions/{id}` against a running demo stack) before
/// it hits that wall, which is as far as this lane's own code goes.
///
/// # Getting a `sessionUrl` to paste in
///
/// This app is a payer's device, not a merchant's server (design doc, "The
/// invariant") — it never creates a checkout session itself. Bring up
/// `compose.demo.yml` (`just demo-up`) and create a **hosted** session with
/// the demo tenant's secret key (`config/application.yml`'s
/// `pk_test_acmecameroonsandbox01`, paired with the demo deployment's own
/// secret key — see `docs/flows/hosted-checkout.md`), e.g.:
///
/// ```bash
/// curl -s http://localhost:8080/v1/checkout/sessions \
///   -u sk_test_…: \
///   -d amount=5000 -d currency=xaf -d ui_mode=hosted \
///   -d 'success_url=https://example.com/thanks' \
///   -d 'cancel_url=https://example.com/cancel'
/// ```
///
/// and paste the response's `url` below.
library;

import 'package:flutter/material.dart';
import 'package:vpay_checkout_flutter/vpay_checkout_flutter.dart';

void main() {
  runApp(const VpayCheckoutExampleApp());
}

class VpayCheckoutExampleApp extends StatelessWidget {
  const VpayCheckoutExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vpay_checkout_flutter example',
      home: const _CheckoutPage(),
    );
  }
}

class _CheckoutPage extends StatefulWidget {
  const _CheckoutPage();

  @override
  State<_CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<_CheckoutPage> {
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'http://localhost:8080',
  );
  final TextEditingController _publishableKeyController = TextEditingController(
    text: 'pk_test_acmecameroonsandbox01',
  );
  final TextEditingController _sessionUrlController = TextEditingController();

  String _status = 'Idle.';
  bool _running = false;

  Future<void> _start() async {
    setState(() {
      _running = true;
      _status = 'Starting…';
    });
    try {
      final checkout = VpayCheckout(
        baseUrl: _baseUrlController.text.trim(),
        publishableKey: _publishableKeyController.text.trim(),
        // The demo stack is plain http:// — see the module doc comment.
        allowInsecureBaseUrl: true,
      );
      final VpayCheckoutResult result = await checkout.start(
        _sessionUrlController.text.trim(),
      );
      setState(() => _status = result.toString());
    } on UnimplementedError catch (e) {
      setState(
        () => _status =
            'Pre-flight ran; the platform window itself is not built yet '
            '(Lane C): $e',
      );
    } on Object catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _publishableKeyController.dispose();
    _sessionUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('vpay_checkout_flutter example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(labelText: 'API base URL'),
            ),
            TextField(
              controller: _publishableKeyController,
              decoration: const InputDecoration(labelText: 'Publishable key'),
            ),
            TextField(
              controller: _sessionUrlController,
              decoration: const InputDecoration(
                labelText: 'Hosted checkout session url (from your server)',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _running ? null : _start,
              child: const Text('Start checkout'),
            ),
            const SizedBox(height: 16),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
