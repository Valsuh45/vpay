import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vpay_checkout_flutter/vpay_checkout_flutter.dart';

const _piSecret = 'pi_123_secret_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _csSecret = 'cs_123_secret_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _sessionUrl =
    'https://checkout.example/c/cs_123?key=pk_test_1#$_csSecret';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

Map<String, Object?> _paymentIntentJson(String status) => {
  'id': 'pi_123',
  'object': 'payment_intent',
  'amount': 5000,
  'currency': 'xaf',
  'status': status,
  'payment_method_types': ['mtn_momo'],
  'next_action': null,
  'last_payment_error': null,
  'metadata': <String, Object?>{},
  'description': null,
  'created': 1700000000,
  'livemode': false,
  'client_secret': _piSecret,
};

Map<String, Object?> _sessionJson({String uiMode = 'hosted'}) => {
  'id': 'cs_123',
  'object': 'checkout.session',
  'livemode': false,
  'payment_intent': _paymentIntentJson('requires_payment_method'),
  'ui_mode': uiMode,
  'status': 'open',
  'payment_status': 'unpaid',
  'success_url': 'https://shop.example/thanks',
  'cancel_url': 'https://shop.example/cancel',
  'return_url': null,
  'url': _sessionUrl,
  'expires_at': 1700086400,
  'created': 1700000000,
  'client_secret': _csSecret,
};

/// A clock that advances instantly rather than waiting real time — keeps
/// the "still processing" tests below from actually burning the default
/// polling budgets in wall-clock seconds.
class _FakeClock extends VpayClock {
  _FakeClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) async {
    _now = _now.add(duration);
  }
}

class _FakePlatform extends VpayCheckoutPlatform {
  _FakePlatform(this.outcome);

  final CheckoutWindowOutcome outcome;
  bool shown = false;

  @override
  Future<void> show({
    required String url,
    required List<StopUrlSpec> stopUrls,
    required bool allowInsecureUrl,
  }) async {
    shown = true;
  }

  @override
  Future<void> dismiss() async {}

  @override
  Stream<CheckoutWindowEvent> get windowEvents =>
      Stream.value(CheckoutWindowEvent(outcome: outcome));
}

void main() {
  tearDown(() {
    VpayCheckoutPlatform.instance = const UnimplementedVpayCheckoutPlatform();
  });

  group('VpayCheckout.start — no platform host exists yet (Lane C)', () {
    test(
      'throws UnimplementedError once it reaches the platform seam',
      () async {
        final checkout = VpayCheckout(
          baseUrl: 'https://api.example',
          publishableKey: 'pk_test_1',
          httpClient: MockClient((request) async => _json(_sessionJson())),
        );

        await expectLater(
          checkout.start(_sessionUrl),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );
  });

  group(
    'VpayCheckout.start — with a platform host wired in (as Lane C will)',
    () {
      test(
        'a reached stop URL resolves through the poll, not off the URL',
        () async {
          VpayCheckoutPlatform.instance = _FakePlatform(
            CheckoutWindowOutcome.stopUrlReached,
          );
          final checkout = VpayCheckout(
            baseUrl: 'https://api.example',
            publishableKey: 'pk_test_1',
            httpClient: MockClient(
              (request) async => request.url.path.contains('checkout/sessions')
                  ? _json(_sessionJson())
                  : _json(_paymentIntentJson('succeeded')),
            ),
          );

          final result = await checkout.start(_sessionUrl);

          expect(result, isA<VpayCheckoutSucceeded>());
        },
      );

      test(
        'a dismissal with a still-processing intent resolves to pending',
        () async {
          VpayCheckoutPlatform.instance = _FakePlatform(
            CheckoutWindowOutcome.dismissed,
          );
          final checkout = VpayCheckout(
            baseUrl: 'https://api.example',
            publishableKey: 'pk_test_1',
            httpClient: MockClient(
              (request) async => request.url.path.contains('checkout/sessions')
                  ? _json(_sessionJson())
                  : _json(_paymentIntentJson('processing')),
            ),
            clock: _FakeClock(DateTime(2026, 9, 13)),
          );

          final result = await checkout.start(_sessionUrl);

          expect(result, isA<VpayCheckoutPending>());
        },
      );
    },
  );

  group('VpayCheckout.start — an embedded session is refused before any window opens', () {
    test('never calls the platform host at all', () async {
      final fake = _FakePlatform(CheckoutWindowOutcome.dismissed);
      VpayCheckoutPlatform.instance = fake;
      final checkout = VpayCheckout(
        baseUrl: 'https://api.example',
        publishableKey: 'pk_test_1',
        httpClient: MockClient(
          (request) async => _json(_sessionJson(uiMode: 'embedded')),
        ),
      );

      final result = await checkout.start(_sessionUrl);

      expect(result, isA<VpayCheckoutUnresolved>());
      expect(
        (result as VpayCheckoutUnresolved).error.code,
        VpayClientErrorCodes.embeddedSessionNotSupported,
      );
      expect(fake.shown, isFalse);
    });
  });

  group('VpayCheckout.start — a malformed sessionUrl', () {
    test('is refused without any network call', () async {
      var called = false;
      final checkout = VpayCheckout(
        baseUrl: 'https://api.example',
        publishableKey: 'pk_test_1',
        httpClient: MockClient((request) async {
          called = true;
          return _json(_sessionJson());
        }),
      );

      final result = await checkout.start(
        'https://checkout.example/c/cs_123?key=pk_test_1',
      );

      expect(result, isA<VpayCheckoutUnresolved>());
      expect(called, isFalse);
    });
  });
}
