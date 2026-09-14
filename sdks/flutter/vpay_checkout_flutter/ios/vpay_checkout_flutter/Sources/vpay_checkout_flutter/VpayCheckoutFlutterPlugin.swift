// The iOS host (design doc D5) — Lane C
// (docs/plans/2026-09-13-flutter-plugin-brief.md). This class only wires
// Dart's `VpayCheckoutHostApi` calls to presenting/dismissing
// `VpayCheckoutViewController`, and forwards its result back over
// `VpayCheckoutFlutterApi.onWindowEvent`. It decides nothing about the
// outcome itself (D1) — see `VpayCheckoutViewController`'s own header for
// where the actual window lives.
//
// **Compiled by nobody** (this repository has no macOS/iOS toolchain — see
// `docs/plans/2026-09-13-flutter-plugin-brief.md`, "What this host can
// actually verify"). Reviewed by reading only.
import Flutter
import UIKit

public final class VpayCheckoutFlutterPlugin: NSObject, FlutterPlugin, VpayCheckoutHostApi {

  public static func register(with registrar: FlutterPluginRegistrar) {
    let flutterApi = VpayCheckoutFlutterApi(binaryMessenger: registrar.messenger())
    let plugin = VpayCheckoutFlutterPlugin(
      flutterApi: flutterApi,
      presenterProvider: { [weak registrar] in registrar?.viewController }
    )
    VpayCheckoutHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: plugin)
    registrar.publish(plugin)
  }

  private let flutterApi: VpayCheckoutFlutterApiProtocol
  private let presenterProvider: () -> UIViewController?
  private weak var current: VpayCheckoutViewController?

  init(
    flutterApi: VpayCheckoutFlutterApiProtocol,
    presenterProvider: @escaping () -> UIViewController?
  ) {
    self.flutterApi = flutterApi
    self.presenterProvider = presenterProvider
  }

  // VpayCheckoutHostApi — Dart calling into this host. `VpayCheckoutHostApiSetup`
  // (generated) already dispatches both methods inside `Task { @MainActor in … }`,
  // so UIKit calls below run on the main actor without an extra hop.

  public func show(request: ShowCheckoutRequest) async throws {
    guard current == nil else {
      throw PigeonError(
        code: "already_open",
        message: "vpay_checkout_flutter: a checkout window is already open.",
        details: nil
      )
    }
    guard let url = URL(string: request.url) else {
      throw PigeonError(
        code: "invalid_url",
        message: "vpay_checkout_flutter: ShowCheckoutRequest.url is not a valid URL.",
        details: nil
      )
    }
    guard let presenter = presenterProvider() else {
      throw PigeonError(
        code: "no_presenter",
        message: "vpay_checkout_flutter: no view controller to present the checkout window from.",
        details: nil
      )
    }

    let controller = VpayCheckoutViewController(
      checkoutUrl: url,
      stopUrls: request.stopUrls.compactMap { $0 }
    )
    controller.onEvent = { [weak self, weak controller] event in
      self?.current = nil
      let api = self?.flutterApi
      Task { @MainActor in
        try? await api?.onWindowEvent(event: event)
      }
      _ = controller
    }
    current = controller
    presenter.present(controller, animated: true)
  }

  public func dismiss() async throws {
    guard let controller = current else { return }
    controller.reportDismissedIfNeeded()
    controller.presentingViewController?.dismiss(animated: true)
  }
}
