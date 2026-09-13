/// Wire and API types for vpay's `/v1/browser` surface — the Dart port of
/// `sdks/stripe-js/src/types.ts`'s object shapes, narrowed to what this
/// package's read-only, payer-side use needs.
///
/// D6 governs every `toString()` here: a type holding a session URL, a
/// session secret or an intent secret overrides it and renders
/// `[N chars redacted]` for that member — see `src/redaction.dart`.
library;

import 'redaction.dart';

/// `vpay_core::state::IntentStatus` (`docs/flows/payment-lifecycle.md`).
/// There is deliberately no `failed` value — a rail failure returns the
/// intent to `requiresPaymentMethod` with [LastPaymentError] populated.
enum PaymentIntentStatus {
  requiresPaymentMethod,
  requiresAction,
  processing,
  succeeded,
  canceled,

  /// A status this package does not recognise — a future server value an
  /// older client should not crash on. Never produced server-side today;
  /// carried so a poll loop degrades to `VpayCheckoutUnresolved` rather than
  /// throwing when it eventually is.
  unknown;

  static PaymentIntentStatus fromWire(String value) => switch (value) {
    'requires_payment_method' => PaymentIntentStatus.requiresPaymentMethod,
    'requires_action' => PaymentIntentStatus.requiresAction,
    'processing' => PaymentIntentStatus.processing,
    'succeeded' => PaymentIntentStatus.succeeded,
    'canceled' => PaymentIntentStatus.canceled,
    _ => PaymentIntentStatus.unknown,
  };
}

/// `vpay_core::failure`'s closed vocabulary
/// (`docs/flows/failures.md`) — kept as the raw wire string rather than a
/// closed Dart enum: `sdks/stripe-js`'s own `FailureCode` union is typed
/// against the same eleven values, but a Dart `enum` a future twelfth code
/// does not fit would make an old client's poll loop throw where the
/// TypeScript equivalent just carries a new string through. The eleven
/// documented values are asserted by `test/models_test.dart`'s fixtures
/// rather than enforced by the type itself.
typedef FailureCode = String;

/// A rail failure attached to a `requires_payment_method` intent — present
/// only then; there is no `failed` [PaymentIntentStatus].
final class LastPaymentError {
  const LastPaymentError({required this.code, required this.message});

  final FailureCode code;

  /// The rail's own words. Carried as data, not translated here — the same
  /// treatment the hosted checkout page gives it
  /// (`frontends/apps/checkout/src/lib/failures.ts`'s `providerReason`).
  final String message;

  factory LastPaymentError.fromJson(Map<String, Object?> json) =>
      LastPaymentError(
        code: json['code']! as String,
        message: json['message']! as String,
      );
}

/// `vpay_api::model::PaymentIntentWithSecret`: the twelve keys of
/// `PaymentIntentObject` plus the `client_secret` the browser surface
/// flattens in alongside them (D2) — thirteen keys total, the same count
/// `sdks/stripe-js`'s parity row for this type names.
final class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    required this.paymentMethodTypes,
    required this.lastPaymentError,
    required this.metadata,
    required this.description,
    required this.created,
    required this.livemode,
    required this.clientSecret,
  });

  /// `pi_…`.
  final String id;

  /// Integer minor units. XAF is zero-decimal: `5000` means 5,000 FCFA.
  final int amount;

  /// Lowercase ISO 4217 code, e.g. `xaf`.
  final String currency;

  final PaymentIntentStatus status;

  final List<String> paymentMethodTypes;

  /// Present *with* [PaymentIntentStatus.requiresPaymentMethod] — there is
  /// no `failed` status.
  final LastPaymentError? lastPaymentError;

  final Map<String, String> metadata;

  final String? description;

  /// Unix **seconds**, not milliseconds.
  final int created;

  final bool livemode;

  /// `pi_…_secret_…`. Never log this — see [toString].
  final String clientSecret;

  /// `true` once the intent will not change again without a new request.
  /// The Dart port of `sdks/stripe-js/src/client.ts`'s `hasStoppedMoving`:
  /// `requiresPaymentMethod` is terminal **only** with a [lastPaymentError]
  /// — it is also the status of an intent nobody has confirmed yet, and
  /// treating that as final would resolve a poll the instant it started.
  bool get hasStoppedMoving =>
      status == PaymentIntentStatus.succeeded ||
      status == PaymentIntentStatus.canceled ||
      (status == PaymentIntentStatus.requiresPaymentMethod &&
          lastPaymentError != null);

  factory PaymentIntent.fromJson(Map<String, Object?> json) => PaymentIntent(
    id: json['id']! as String,
    amount: json['amount']! as int,
    currency: json['currency']! as String,
    status: PaymentIntentStatus.fromWire(json['status']! as String),
    paymentMethodTypes: (json['payment_method_types']! as List<Object?>)
        .cast<String>(),
    lastPaymentError: json['last_payment_error'] == null
        ? null
        : LastPaymentError.fromJson(
            json['last_payment_error']! as Map<String, Object?>,
          ),
    metadata: (json['metadata']! as Map<Object?, Object?>)
        .cast<String, String>(),
    description: json['description'] as String?,
    created: json['created']! as int,
    livemode: json['livemode']! as bool,
    clientSecret: json['client_secret']! as String,
  );

  static bool isPaymentIntentJson(Object? body) =>
      body is Map && body['object'] == 'payment_intent' && body['id'] is String;

  /// D6: redacts [clientSecret]. Nothing else here is sensitive — an amount,
  /// a currency and a status are not credentials.
  @override
  String toString() =>
      'PaymentIntent(id: $id, status: $status, clientSecret: '
      '${redacted(clientSecret)})';
}

/// `open`, `complete` or `expired` (D10).
enum CheckoutSessionStatus {
  open,
  complete,
  expired,
  unknown;

  static CheckoutSessionStatus fromWire(String value) => switch (value) {
    'open' => CheckoutSessionStatus.open,
    'complete' => CheckoutSessionStatus.complete,
    'expired' => CheckoutSessionStatus.expired,
    _ => CheckoutSessionStatus.unknown,
  };
}

/// `hosted` or `embedded`. D2 refuses `embedded` at the pre-flight.
enum CheckoutUiMode {
  hosted,
  embedded,
  unknown;

  static CheckoutUiMode fromWire(String value) => switch (value) {
    'hosted' => CheckoutUiMode.hosted,
    'embedded' => CheckoutUiMode.embedded,
    _ => CheckoutUiMode.unknown,
  };
}

/// `checkout.session` as `GET /v1/browser/checkout/sessions/{id}` renders
/// it, with `payment_intent` **expanded** (the one place this differs from
/// the merchant SDKs' `CheckoutSession`, mirroring
/// `sdks/stripe-js/src/types.ts`'s own note on the same field) — fourteen
/// keys, `client_secret` included.
final class CheckoutSession {
  const CheckoutSession({
    required this.id,
    required this.livemode,
    required this.paymentIntent,
    required this.uiMode,
    required this.status,
    required this.successUrl,
    required this.cancelUrl,
    required this.url,
    required this.expiresAt,
    required this.created,
    required this.clientSecret,
  });

  /// `cs_…`.
  final String id;

  final bool livemode;

  /// The intent this session drives, expanded — every [PaymentIntent] field,
  /// its own `client_secret` included (D2 item 1: the polling credential).
  final PaymentIntent paymentIntent;

  final CheckoutUiMode uiMode;

  final CheckoutSessionStatus status;

  /// Hosted mode only; `null` on an embedded session. May carry the literal
  /// `{CHECKOUT_SESSION_ID}` (D2) — unsubstituted here, exactly as the
  /// merchant wrote it; substitution happens in `checkout_controller.dart`.
  final String? successUrl;

  /// Hosted mode only; `null` on an embedded session. Same substitution
  /// rule as [successUrl].
  final String? cancelUrl;

  /// The page vpay serves for a hosted session — carries the session's
  /// `client_secret` in its fragment (D6); `null` when embedded.
  final String? url;

  /// Unix **seconds**. 24 h from create (D10).
  final int expiresAt;

  /// Unix **seconds**.
  final int created;

  /// `cs_…_secret_…`. Never log this — see [toString].
  final String clientSecret;

  factory CheckoutSession.fromJson(Map<String, Object?> json) =>
      CheckoutSession(
        id: json['id']! as String,
        livemode: json['livemode']! as bool,
        paymentIntent: PaymentIntent.fromJson(
          json['payment_intent']! as Map<String, Object?>,
        ),
        uiMode: CheckoutUiMode.fromWire(json['ui_mode']! as String),
        status: CheckoutSessionStatus.fromWire(json['status']! as String),
        successUrl: json['success_url'] as String?,
        cancelUrl: json['cancel_url'] as String?,
        url: json['url'] as String?,
        expiresAt: json['expires_at']! as int,
        created: json['created']! as int,
        clientSecret: json['client_secret']! as String,
      );

  static bool isCheckoutSessionJson(Object? body) =>
      body is Map &&
      body['object'] == 'checkout.session' &&
      body['id'] is String;

  /// D6: redacts [url] (carries the session secret in its fragment) and
  /// [clientSecret]. [paymentIntent] renders through its own overridden
  /// [PaymentIntent.toString], so its secret is redacted too rather than
  /// relying on this method to remember to do it a second time.
  @override
  String toString() =>
      'CheckoutSession(id: $id, status: $status, url: ${redacted(url)}, '
      'clientSecret: ${redacted(clientSecret)}, paymentIntent: '
      '$paymentIntent)';
}
