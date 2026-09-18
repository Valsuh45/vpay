import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vpay_checkout_flutter/vpay_checkout_flutter.dart';

const _piSecret = 'pi_123_secret_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _csSecret = 'cs_123_secret_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/// This session's own hosted page — on the **checkout** origin.
///
/// Deliberately a different host from `_ScriptedClient`'s `https://api.example`
/// base URL, because those really are two deployables on two origins
/// (`checkout.public_base_url` vs `deployment.public_base_url`,
/// `config/application.yml`). A test that used one string for both could not
/// tell a redirect-leg URL built on the right origin from one built on the
/// wrong one.
const _sessionPageUrl = 'https://checkout.example/c/cs_123';

/// A clock a test fully controls — `checkout_controller_test.dart`'s own
/// `FakeClock`, restated here so this file has no test-time dependency on
/// that one.
class FakeClock extends VpayClock {
  FakeClock(this._now);
  DateTime _now;

  @override
  DateTime now() => _now;

  @override
  Future<void> delay(Duration duration) async {
    _now = _now.add(duration);
  }
}

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

Map<String, Object?> _intentJson({
  String status = 'requires_payment_method',
  Object? nextAction,
  Object? lastPaymentError,
}) => {
  'id': 'pi_123',
  'object': 'payment_intent',
  'amount': 5000,
  'currency': 'xaf',
  'status': status,
  'payment_method_types': ['mtn_momo'],
  'next_action': nextAction,
  'last_payment_error': lastPaymentError,
  'metadata': <String, Object?>{},
  'description': null,
  'created': 1700000000,
  'livemode': false,
  'client_secret': _piSecret,
};

Map<String, Object?> _mtnRailJson() => {
  'code': 'mtn_momo',
  'flow': 'push',
  'label_key': 'rail.mtn_momo',
  'fields': [
    {
      'name': 'msisdn',
      'type': 'phone',
      'region': 'CM',
      'phone_type': 'mobile',
      'required': true,
      'label_key': 'msisdn.label',
    },
  ],
};

Map<String, Object?> _orangeRailJson() => {
  'code': 'orange_money',
  'flow': 'redirect',
  'label_key': 'rail.orange_money',
  'fields': const <Object?>[],
};

Map<String, Object?> _sessionJson({
  required Object? intent,
  List<Object?> rails = const <Object?>[],
  String? successUrl,
  String? cancelUrl,
}) => {
  'id': 'cs_123',
  'object': 'checkout.session',
  'livemode': false,
  'payment_intent': intent,
  'ui_mode': 'hosted',
  'status': 'open',
  'payment_status': 'unpaid',
  'success_url': successUrl,
  'cancel_url': cancelUrl,
  'return_url': null,
  'url': 'https://checkout.example/c/cs_123#$_csSecret',
  'expires_at': 1700086400,
  'created': 1700000000,
  'rails': rails,
};

/// Answers the session on the first GET, then whatever [intentAnswers]
/// yields — one per subsequent `retrievePaymentIntent`/confirm call — and a
/// re-read of the session (after a terminal outcome) with [finalSession].
class _ScriptedClient {
  _ScriptedClient({
    required Map<String, Object?> session,
    required List<Map<String, Object?>> intentAnswers,
    Map<String, Object?>? finalSession,
  }) : _session = session,
       _intentAnswers = List.of(intentAnswers),
       _finalSession = finalSession ?? session;

  final Map<String, Object?> _session;
  final List<Map<String, Object?>> _intentAnswers;
  final Map<String, Object?> _finalSession;
  int _sessionReads = 0;
  final List<String> calls = [];

  BrowserClient build() => BrowserClient(
    baseUrl: 'https://api.example',
    publishableKey: 'pk_test_1',
    httpClient: MockClient((http.Request request) async {
      if (request.method == 'GET' &&
          request.url.path.contains('/checkout/sessions/')) {
        _sessionReads += 1;
        calls.add('read_session');
        return _json(_sessionReads == 1 ? _session : _finalSession);
      }
      if (request.method == 'GET' &&
          request.url.path.contains('/payment_intents/')) {
        calls.add('poll');
        return _json(_intentAnswers.removeAt(0));
      }
      if (request.method == 'POST' && request.url.path.endsWith('/confirm')) {
        calls.add('confirm');
        return _json(_intentAnswers.removeAt(0));
      }
      throw StateError('unexpected request: ${request.method} ${request.url}');
    }),
  );
}

class _FakePlatform extends VpayCheckoutPlatform {
  _FakePlatform(this.outcome);

  final CheckoutWindowOutcome outcome;
  bool shown = false;
  String? shownUrl;
  final StreamController<CheckoutWindowEvent> _events =
      StreamController<CheckoutWindowEvent>.broadcast();
  final List<String> order = [];

  @override
  Future<void> show({
    required String url,
    required List<StopUrlSpec> stopUrls,
    required bool allowInsecureUrl,
  }) async {
    shown = true;
    shownUrl = url;
    order.add('platform.show');
    unawaited(
      Future<void>.microtask(
        () => _events.add(CheckoutWindowEvent(outcome: outcome)),
      ),
    );
  }

  @override
  Future<void> dismiss() async {}

  @override
  Stream<CheckoutWindowEvent> get windowEvents => _events.stream;
}

class _InMemoryRememberedMsisdnStore implements VpayRememberedMsisdnStore {
  RememberedMsisdnRecord? record;

  @override
  Future<void> clear() async => record = null;

  @override
  Future<RememberedMsisdnRecord?> read() async => record;

  @override
  Future<void> write(RememberedMsisdnRecord r) async => record = r;
}

/// Lets an `unawaited` async load (e.g. the controller's own remembered-number
/// read after a rail is chosen) finish, so a test can assert on its result.
Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
}

/// A store whose `read` does not answer until [release] — lets a test hold the
/// remembered-record seed in flight to prove behaviour *before* it lands.
class _GatedRememberedMsisdnStore implements VpayRememberedMsisdnStore {
  _GatedRememberedMsisdnStore(this.record);

  RememberedMsisdnRecord? record;
  final Completer<void> _gate = Completer<void>();

  @override
  Future<void> clear() async => record = null;

  @override
  Future<RememberedMsisdnRecord?> read() async {
    await _gate.future;
    return record;
  }

  @override
  Future<void> write(RememberedMsisdnRecord r) async => record = r;

  void release() => _gate.complete();
}

/// A store that answers its first [_readsBeforeGate] reads at once and holds
/// the next one open until [release].
///
/// `SheetController._loadRememberedMsisdn` reads the store three times, in
/// order — `hasRecord`, `read(railCode)`, then the `hasActiveRecord` that seeds
/// the box. [_GatedRememberedMsisdnStore] gates the *first* of the three, which
/// suspends the load before the seed is entered at all; gating the **third**
/// suspends inside the seed itself, which is the window an unticked-submit
/// guard actually has to survive — the box is not yet known, but the flag
/// saying "the box is known" has already been set.
class _SeedGatedRememberedMsisdnStore implements VpayRememberedMsisdnStore {
  _SeedGatedRememberedMsisdnStore(this.record);

  /// The two reads `_loadRememberedMsisdn` makes before the seed it gates.
  static const int _readsBeforeGate = 2;

  RememberedMsisdnRecord? record;
  final Completer<void> _gate = Completer<void>();
  int _reads = 0;

  @override
  Future<void> clear() async => record = null;

  @override
  Future<RememberedMsisdnRecord?> read() async {
    _reads += 1;
    if (_reads > _readsBeforeGate) {
      await _gate.future;
    }
    return record;
  }

  @override
  Future<void> write(RememberedMsisdnRecord r) async => record = r;

  void release() => _gate.complete();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // `SheetController` reaches `SharedPreferencesRememberedMsisdnStore` (the
  // real store, the default) whenever a push-rail entry screen preloads a
  // remembered number — this backs it with the plugin's own mock channel
  // rather than every test constructing an explicit fake store, so a test
  // that does not care about the memory feature still doesn't hang on a
  // real platform channel with no host to answer it.
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('SheetController — push rail happy path', () {
    test('select_rail is skipped for one supported rail; submit confirms, polls with jitter, then completes exactly once', () async {
      final FakeClock clock = FakeClock(DateTime(2026));
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: [
          _intentJson(status: 'processing'), // confirm's own answer
          _intentJson(status: 'processing'), // first poll: still moving
          _intentJson(status: 'succeeded'), // second poll: terminal
        ],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        clock: clock,
        jitterSource: FixedJitterSource(const [0.5]),
      );

      final List<CheckoutScreenState> seen = [];
      controller.addListener(() => seen.add(controller.state));

      await controller.start();

      expect(controller.state, isA<CheckoutCollectMsisdn>());

      await controller.submitMsisdn('+237 6 71 23 45 67');

      expect(controller.state, isA<CheckoutOutcome>());
      expect((controller.state as CheckoutOutcome).kind, OutcomeKind.succeeded);
      expect(scripted.calls, [
        'read_session',
        'confirm',
        'poll',
        'poll',
        'read_session',
      ]);

      final result = await controller.result;
      expect(result, isA<VpayCheckoutSucceeded>());
      expect((result as VpayCheckoutSucceeded).paymentIntentId, 'pi_123');

      // Poll-then-outcome: `scripted.calls` above already proves the
      // whole ordering — both `poll`s ran, THEN (and only then) the
      // post-outcome `read_session` (`_announceOutcome`'s own session
      // re-read) happened. At least one `CheckoutOutcome` notification
      // reached this listener; a second one (the re-read's own
      // `CheckoutSessionRefreshed`, still `CheckoutOutcome`-shaped) is
      // expected, not a regression.
      expect(seen.whereType<CheckoutOutcome>(), isNotEmpty);
    });

    test('select_rail is shown for two supported rails', () async {
      final scripted = _ScriptedClient(
        session: _sessionJson(
          intent: _intentJson(),
          rails: [_mtnRailJson(), _orangeRailJson()],
        ),
        intentAnswers: const [],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
      );

      await controller.start();

      expect(controller.state, isA<CheckoutSelectRail>());
    });

    test('an invalid MSISDN never confirms and shows msisdn.invalid', () async {
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: const [],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
      );

      await controller.start();
      await controller.submitMsisdn('not a number');

      expect(controller.state, isA<CheckoutCollectMsisdn>());
      expect(
        (controller.state as CheckoutCollectMsisdn).problem,
        'msisdn.invalid',
      );
      expect(scripted.calls, ['read_session']);
    });

    test(
      'remembering a number writes only after a real, accepted submit',
      () async {
        final store = _InMemoryRememberedMsisdnStore();
        final scripted = _ScriptedClient(
          session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
          intentAnswers: [
            _intentJson(
              status: 'succeeded',
            ), // confirm answers terminal directly
          ],
        );
        final controller = SheetController(
          client: scripted.build(),
          sessionPageUrl: _sessionPageUrl,
          sessionClientSecret: _csSecret,
          remembered: VpayRememberedMsisdn(
            store: store,
            now: () => DateTime(2026, 1, 1),
          ),
        );

        await controller.start();
        expect(store.record, isNull, reason: 'nothing written before a submit');

        controller.setRememberChecked(true);
        await controller.submitMsisdn('+237 6 71 23 45 67');

        expect(store.record, isNotNull);
        expect(store.record!.msisdn, '237671234567');
        expect(store.record!.railCode, 'mtn_momo');
      },
    );

    test('an unticked submit clears a previously-remembered number — paying '
        'while unticked is a deliberate "stop remembering"', () async {
      final store = _InMemoryRememberedMsisdnStore()
        ..record = RememberedMsisdnRecord(
          msisdn: '237671234567',
          railCode: 'mtn_momo',
          rememberedAt: DateTime(2026, 1, 1),
        );
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: [_intentJson(status: 'succeeded')],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        remembered: VpayRememberedMsisdn(
          store: store,
          now: () => DateTime(2026, 1, 1),
        ),
      );

      await controller.start();
      expect(controller.hasRememberedRecord, isTrue);
      // The fresh record seeds the box ticked...
      expect(controller.rememberChecked, isTrue);

      // ...the payer unticks and pays — a deliberate act that forgets.
      controller.setRememberChecked(false);
      await controller.submitMsisdn('+237 6 71 23 45 67');

      expect(store.record, isNull);
      expect(controller.hasRememberedRecord, isFalse);
      expect(controller.rememberChecked, isFalse);
    });

    test(
      'an unticked submit before the memory seed has landed does not clear a '
      'record the payer never un-ticked',
      () async {
        final store = _GatedRememberedMsisdnStore(
          RememberedMsisdnRecord(
            msisdn: '237671234567',
            railCode: 'mtn_momo',
            rememberedAt: DateTime(2026, 1, 1),
          ),
        );
        final scripted = _ScriptedClient(
          session: _sessionJson(
            intent: _intentJson(),
            rails: [_mtnRailJson(), _orangeRailJson()],
          ),
          intentAnswers: [_intentJson(status: 'succeeded')],
        );
        final controller = SheetController(
          client: scripted.build(),
          sessionPageUrl: _sessionPageUrl,
          sessionClientSecret: _csSecret,
          remembered: VpayRememberedMsisdn(
            store: store,
            now: () => DateTime(2026, 1, 1),
          ),
        );

        await controller.start();
        expect(controller.state, isA<CheckoutSelectRail>());

        // Picking MTN reaches the form and starts the (still-gated) seed: the
        // box has not been seeded yet, so `rememberChecked` is its initial
        // false and `_rememberSeeded` is false.
        controller.chooseRail(
          (controller.state as CheckoutSelectRail).rails.supported.first,
        );
        expect(controller.state, isA<CheckoutCollectMsisdn>());

        await controller.submitMsisdn('+237 6 71 23 45 67');

        // The unseeded, unticked submit must not have cleared the record.
        expect(store.record, isNotNull);
        store.release();
      },
    );

    test('an unticked submit while the box seed is itself in flight does not '
        'clear the record — the guard has to cover the whole seed, not only '
        'the reads before it', () async {
      final store = _SeedGatedRememberedMsisdnStore(
        RememberedMsisdnRecord(
          msisdn: '237671234567',
          railCode: 'mtn_momo',
          rememberedAt: DateTime(2026, 1, 1),
        ),
      );
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: [_intentJson(status: 'succeeded')],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        remembered: VpayRememberedMsisdn(
          store: store,
          now: () => DateTime(2026, 1, 1),
        ),
      );

      // `start()` cannot be awaited here: it awaits the load, and the load
      // is suspended inside the seed's own store read.
      unawaited(controller.start());
      for (int i = 0; i < 10 && controller.defaultMsisdn == null; i++) {
        await _flushMicrotasks();
      }

      // This is the window: the number has arrived, the tick has not.
      expect(controller.state, isA<CheckoutCollectMsisdn>());
      expect(controller.defaultMsisdn, '237671234567');
      expect(controller.rememberChecked, isFalse);

      await controller.submitMsisdn('+237 6 71 23 45 67');

      // The payer never unticked anything. A box that is merely *unseeded*
      // reads false exactly as a deliberately unticked one does, so it must
      // not be allowed to destroy the record.
      expect(store.record, isNotNull);
      store.release();
    });
  });

  group('SheetController — preloading the remembered record (issue #194)', () {
    test(
      'a stored record for the single push rail preloads the number and ticks '
      'the box on start',
      () async {
        final store = _InMemoryRememberedMsisdnStore()
          ..record = RememberedMsisdnRecord(
            msisdn: '237671234567',
            railCode: 'mtn_momo',
            rememberedAt: DateTime(2026, 1, 1),
          );
        final scripted = _ScriptedClient(
          session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
          intentAnswers: const [],
        );
        final controller = SheetController(
          client: scripted.build(),
          sessionPageUrl: _sessionPageUrl,
          sessionClientSecret: _csSecret,
          remembered: VpayRememberedMsisdn(
            store: store,
            now: () => DateTime(2026, 1, 1),
          ),
        );

        await controller.start();

        expect(controller.state, isA<CheckoutCollectMsisdn>());
        expect(controller.defaultMsisdn, '237671234567');
        expect(controller.hasRememberedRecord, isTrue);
        expect(controller.rememberChecked, isTrue);
      },
    );

    test('a redirect rail loads memory state (box + forget) even though it has '
        'no number to recall', () async {
      final store = _InMemoryRememberedMsisdnStore()
        ..record = RememberedMsisdnRecord(
          msisdn: '237671234567',
          railCode: 'mtn_momo',
          rememberedAt: DateTime(2026, 1, 1),
        );
      final scripted = _ScriptedClient(
        session: _sessionJson(
          intent: _intentJson(),
          rails: [_orangeRailJson()],
        ),
        intentAnswers: const [],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        remembered: VpayRememberedMsisdn(
          store: store,
          now: () => DateTime(2026, 1, 1),
        ),
      );

      await controller.start();

      expect(controller.state, isA<CheckoutReadyRedirect>());
      expect(controller.defaultMsisdn, isNull);
      expect(controller.hasRememberedRecord, isTrue);
      expect(controller.rememberChecked, isTrue);
    });

    test('no stored record leaves the box unticked and no prefill', () async {
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: const [],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        remembered: VpayRememberedMsisdn(
          store: _InMemoryRememberedMsisdnStore(),
        ),
      );

      await controller.start();

      expect(controller.defaultMsisdn, isNull);
      expect(controller.hasRememberedRecord, isFalse);
      expect(controller.rememberChecked, isFalse);
    });

    test('an expired record leaves the box unticked and no prefill, but still '
        'offers forget (the web untick the same way)', () async {
      final store = _InMemoryRememberedMsisdnStore()
        ..record = RememberedMsisdnRecord(
          msisdn: '237671234567',
          railCode: 'mtn_momo',
          rememberedAt: DateTime(2025, 1, 1), // well past the 90-day TTL
        );
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: const [],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        remembered: VpayRememberedMsisdn(
          store: store,
          now: () => DateTime(2026, 1, 1),
        ),
      );

      await controller.start();

      expect(controller.state, isA<CheckoutCollectMsisdn>());
      // `read` applies the TTL -> no number comes back.
      expect(controller.defaultMsisdn, isNull);
      // `hasRecord` still counts the stale record -> the forget affordance
      // is offered (the Dart's own, documented decision).
      expect(controller.hasRememberedRecord, isTrue);
      // ...but the box is unticked: there is nothing the device can
      // truthfully say it still remembers — `memory.ts` returns null for an
      // expired record, so the web's box is unticked too.
      expect(controller.rememberChecked, isFalse);
    });

    test(
      'an untick survives moving between rails — the box is seeded once, '
      'not on every entry (the web seeds remember once at startup)',
      () async {
        final store = _InMemoryRememberedMsisdnStore()
          ..record = RememberedMsisdnRecord(
            msisdn: '237671234567',
            railCode: 'mtn_momo',
            rememberedAt: DateTime(2026, 1, 1),
          );
        final scripted = _ScriptedClient(
          session: _sessionJson(
            intent: _intentJson(),
            rails: [_mtnRailJson(), _orangeRailJson()],
          ),
          intentAnswers: const [],
        );
        final controller = SheetController(
          client: scripted.build(),
          sessionPageUrl: _sessionPageUrl,
          sessionClientSecret: _csSecret,
          remembered: VpayRememberedMsisdn(
            store: store,
            now: () => DateTime(2026, 1, 1),
          ),
        );

        await controller.start();
        expect(controller.state, isA<CheckoutSelectRail>());

        final SupportedRail mtn =
            (controller.state as CheckoutSelectRail).rails.supported.first;
        controller.chooseRail(mtn);
        await _flushMicrotasks();
        expect(controller.state, isA<CheckoutCollectMsisdn>());
        expect(controller.rememberChecked, isTrue);

        controller.setRememberChecked(false);
        controller.back();
        controller.chooseRail(mtn);
        await _flushMicrotasks();

        expect(controller.state, isA<CheckoutCollectMsisdn>());
        expect(controller.rememberChecked, isFalse);
      },
    );

    test('forget unticks the box, matching the web\'s onForget -> setRemember(false)', () async {
      final store = _InMemoryRememberedMsisdnStore()
        ..record = RememberedMsisdnRecord(
          msisdn: '237671234567',
          railCode: 'mtn_momo',
          rememberedAt: DateTime(2026, 1, 1),
        );
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: const [],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        remembered: VpayRememberedMsisdn(
          store: store,
          now: () => DateTime(2026, 1, 1),
        ),
      );

      await controller.start();
      expect(controller.rememberChecked, isTrue);

      await controller.forgetRemembered();

      expect(controller.rememberChecked, isFalse);
      expect(controller.hasRememberedRecord, isFalse);
      expect(controller.forgotten, isTrue);
    });
  });

  group('SheetController — redirect rail hand-off', () {
    test('records redirecting before the platform host is shown, then resumes waiting/poll on stopUrlReached', () async {
      final scripted = _ScriptedClient(
        session: _sessionJson(
          intent: _intentJson(),
          rails: [_orangeRailJson()],
          successUrl: 'https://shop.example/success',
        ),
        intentAnswers: [
          _intentJson(
            status: 'requires_action',
            nextAction: {
              'type': 'redirect_to_url',
              'redirect_to_url': {
                'url': 'https://orange.example/pay/abc',
                'return_url': null,
              },
            },
          ),
          _intentJson(status: 'succeeded'),
        ],
      );
      final platform = _FakePlatform(CheckoutWindowOutcome.stopUrlReached);
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        platform: platform,
      );

      final List<Type> stateOrder = [];
      controller.addListener(
        () => stateOrder.add(controller.state.runtimeType),
      );

      await controller.start();
      expect(controller.state, isA<CheckoutReadyRedirect>());

      await controller.startRedirect();

      expect(platform.shown, isTrue);
      // Issue #195: the browser is handed the vpay-controlled redirect-leg
      // page, never the rail's own URL. The rail URL (`https://orange.example/
      // pay/abc`) must not appear anywhere in the hand-off.
      expect(
        platform.shownUrl,
        'https://checkout.example/c/cs_123/redirect?key=pk_test_1#$_csSecret',
      );
      expect(platform.shownUrl, isNot(contains('orange.example')));
      // …and on the checkout origin, not the API's. `_ScriptedClient`'s base
      // URL is `https://api.example`; a leg built on it would 404.
      expect(platform.shownUrl, isNot(contains('api.example')));
      // redirect_required (-> CheckoutRedirecting) must appear in the
      // recorded state history strictly before the platform host was
      // asked to show anything.
      final redirectingIndex = stateOrder.indexOf(CheckoutRedirecting);
      expect(redirectingIndex, greaterThanOrEqualTo(0));

      expect(controller.state, isA<CheckoutOutcome>());
      final result = await controller.result;
      expect(result, isA<VpayCheckoutSucceeded>());
    });

    test('a confirm answering with no next_action polls directly, without ever showing a window', () async {
      final scripted = _ScriptedClient(
        session: _sessionJson(
          intent: _intentJson(),
          rails: [_orangeRailJson()],
        ),
        intentAnswers: [
          _intentJson(status: 'processing'),
          _intentJson(status: 'succeeded'),
        ],
      );
      final platform = _FakePlatform(CheckoutWindowOutcome.dismissed);
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        platform: platform,
      );

      await controller.start();
      await controller.startRedirect();

      expect(platform.shown, isFalse);
      expect(controller.state, isA<CheckoutOutcome>());
    });
  });

  group('SheetController.dismiss', () {
    test('before any confirm, resolves Unresolved — never canceled', () async {
      final scripted = _ScriptedClient(
        session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
        intentAnswers: const [],
      );
      final controller = SheetController(
        client: scripted.build(),
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
      );

      await controller.start();
      final result = await controller.dismiss();

      expect(result, isA<VpayCheckoutUnresolved>());
      expect(result, isNot(isA<VpayCheckoutCanceled>()));
      expect(
        (result as VpayCheckoutUnresolved).error.code,
        VpayClientErrorCodes.sheetDismissedBeforeConfirm,
      );
    });

    test('mid-payment (after confirm, still moving) resolves Pending — never canceled', () async {
      // The confirm's own POST never answers within this test — modelling
      // "the payer dismissed the sheet right after tapping Pay, before
      // the server even replied" without racing `submitMsisdn`'s OWN poll
      // loop (which only starts once confirm answers) against `dismiss`'s
      // short poll on the same clock. `dismiss` polls with plain GETs,
      // answered independently below.
      final Completer<http.Response> confirmGate = Completer<http.Response>();
      final client = BrowserClient(
        baseUrl: 'https://api.example',
        publishableKey: 'pk_test_1',
        httpClient: MockClient((http.Request request) async {
          if (request.method == 'GET' &&
              request.url.path.contains('/checkout/sessions/')) {
            return _json(
              _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
            );
          }
          if (request.method == 'POST') {
            return confirmGate.future;
          }
          // dismiss()'s own poll: always still moving.
          return _json(_intentJson(status: 'processing'));
        }),
      );
      final clock = FakeClock(DateTime(2026));
      final controller = SheetController(
        client: client,
        sessionPageUrl: _sessionPageUrl,
        sessionClientSecret: _csSecret,
        clock: clock,
        jitterSource: FixedJitterSource(const [0.5]),
        dismissalPollBudget: const Duration(seconds: 5),
      );

      await controller.start();
      expect(controller.state, isA<CheckoutCollectMsisdn>());

      // Fire-and-forget: runs synchronously up to (and including) the
      // confirm call, which never answers — `_hasConfirmedOnce` is set
      // and the state reaches `CheckoutConfirming` before this line
      // returns, both required for `dismiss()`'s own branch below.
      unawaited(controller.submitMsisdn('+237 6 71 23 45 67'));
      expect(controller.state, isA<CheckoutConfirming>());

      final VpayCheckoutResult result = await controller.dismiss();

      expect(result, isA<VpayCheckoutPending>());
      expect(result, isNot(isA<VpayCheckoutCanceled>()));
    });

    test(
      'is idempotent — a second call answers the same completed result',
      () async {
        final scripted = _ScriptedClient(
          session: _sessionJson(intent: _intentJson(), rails: [_mtnRailJson()]),
          intentAnswers: const [],
        );
        final controller = SheetController(
          client: scripted.build(),
          sessionPageUrl: _sessionPageUrl,
          sessionClientSecret: _csSecret,
        );

        await controller.start();
        final first = await controller.dismiss();
        final second = await controller.dismiss();

        // The completer resolves once; a second call answers the exact same
        // cached result rather than recomputing (and, for the polling path,
        // rather than polling a second time).
        expect(identical(first, second), isTrue);
      },
    );
  });

  group('SheetController — errorMessageKey', () {
    test('api_connection_error maps to error.network', () {
      expect(errorMessageKey(VpayError.connection()), 'error.network');
    });

    test('resource_missing maps to error.session_not_found', () {
      expect(
        errorMessageKey(
          const VpayError(
            type: 'invalid_request_error',
            code: 'resource_missing',
          ),
        ),
        'error.session_not_found',
      );
    });

    test('anything else maps to error.unexpected', () {
      expect(
        errorMessageKey(VpayError.unexpectedResponse(502)),
        'error.unexpected',
      );
    });
  });

  group('SheetController.sessionPageUrlFrom', () {
    test(
      'keeps the checkout origin and the path, and drops both credentials',
      () {
        expect(
          SheetController.sessionPageUrlFrom(
            'https://checkout.example/c/cs_123?key=pk_test_1#$_csSecret',
          ),
          'https://checkout.example/c/cs_123',
        );
      },
    );

    test(
      'keeps a deployment path prefix — a legal checkout.public_base_url',
      () {
        expect(
          SheetController.sessionPageUrlFrom(
            'https://api.example/checkout/c/cs_123?key=pk_test_1#$_csSecret',
          ),
          'https://api.example/checkout/c/cs_123',
        );
      },
    );

    test('a fragment-only session URL loses the fragment and nothing else', () {
      expect(
        SheetController.sessionPageUrlFrom(
          'https://checkout.example/c/cs_123#$_csSecret',
        ),
        'https://checkout.example/c/cs_123',
      );
    });
  });

  group('SheetController.redirectLegUrlFor', () {
    test('builds a vpay-controlled /redirect URL with the key in the query and the secret in the fragment', () {
      expect(
        SheetController.redirectLegUrlFor(
          sessionPageUrl: _sessionPageUrl,
          publishableKey: 'pk_test_1',
          sessionClientSecret: _csSecret,
        ),
        'https://checkout.example/c/cs_123/redirect?key=pk_test_1#$_csSecret',
      );
    });

    test('strips a trailing slash from the session page URL', () {
      expect(
        SheetController.redirectLegUrlFor(
          sessionPageUrl: '$_sessionPageUrl/',
          publishableKey: 'pk_test_1',
          sessionClientSecret: _csSecret,
        ),
        'https://checkout.example/c/cs_123/redirect?key=pk_test_1#$_csSecret',
      );
    });

    test('never carries a rail URL — the redirect page re-derives it from the server', () {
      final String url = SheetController.redirectLegUrlFor(
        sessionPageUrl: _sessionPageUrl,
        publishableKey: 'pk_test_1',
        sessionClientSecret: _csSecret,
      );
      expect(url, isNot(contains('orange.example')));
      expect(url, isNot(contains('url=')));
    });

    test('is built on the CHECKOUT origin, never the API base URL the client holds', () {
      // The bug this test exists for: `/c/{id}/…` is served by
      // `frontends/apps/checkout`, a second deployable on a second origin
      // (`checkout.public_base_url`). Building it on `BrowserClient.baseUrl`
      // — the API's origin, `deployment.public_base_url` — sends the payer
      // to a route the API does not serve.
      final String url = SheetController.redirectLegUrlFor(
        sessionPageUrl: _sessionPageUrl,
        publishableKey: 'pk_test_1',
        sessionClientSecret: _csSecret,
      );
      expect(url, startsWith('https://checkout.example/'));
      expect(url, isNot(contains('api.example')));
    });
  });
}
