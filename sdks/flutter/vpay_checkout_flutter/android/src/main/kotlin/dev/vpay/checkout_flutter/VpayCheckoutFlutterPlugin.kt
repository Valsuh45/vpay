// The Android host (design doc D5) — Lane C
// (docs/plans/2026-09-13-flutter-plugin-brief.md). This class only wires
// Dart's `VpayCheckoutHostApi` calls to launching/closing
// `VpayCheckoutActivity`, and forwards the Activity's result back over
// `VpayCheckoutFlutterApi.onWindowEvent`. It decides nothing about the
// outcome itself (D1) — see `VpayCheckoutActivity`'s own header for where
// the actual window lives.
package dev.vpay.checkout_flutter

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** vpay_checkout_flutter's Android plugin entry point. */
class VpayCheckoutFlutterPlugin :
  FlutterPlugin,
  ActivityAware,
  VpayCheckoutHostApi,
  ActivityResultListener {

  private var flutterApi: VpayCheckoutFlutterApi? = null
  private var activity: Activity? = null
  private var activityBinding: ActivityPluginBinding? = null
  private val scope = CoroutineScope(Dispatchers.Main)

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    VpayCheckoutHostApi.setUp(binding.binaryMessenger, this)
    flutterApi = VpayCheckoutFlutterApi(binding.binaryMessenger)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    VpayCheckoutHostApi.setUp(binding.binaryMessenger, null)
    flutterApi = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    activityBinding = binding
    binding.addActivityResultListener(this)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }

  override fun onDetachedFromActivity() {
    activityBinding?.removeActivityResultListener(this)
    activityBinding = null
    activity = null
  }

  // VpayCheckoutHostApi — Dart calling into this host.

  override suspend fun show(request: ShowCheckoutRequest) {
    val hostActivity =
      activity
        ?: throw FlutterError(
          "no_activity",
          "vpay_checkout_flutter: show() called with no Activity attached.",
          null,
        )
    if (VpayCheckoutActivity.isOpen()) {
      throw FlutterError(
        "already_open",
        "vpay_checkout_flutter: a checkout window is already open.",
        null,
      )
    }
    hostActivity.startActivityForResult(
      VpayCheckoutActivity.buildIntent(hostActivity, request),
      VpayCheckoutActivity.REQUEST_CODE,
    )
  }

  override suspend fun dismiss() {
    VpayCheckoutActivity.dismissIfOpen()
  }

  // ActivityResultListener — VpayCheckoutActivity reporting back.

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != VpayCheckoutActivity.REQUEST_CODE) {
      return false
    }
    val event = VpayCheckoutActivity.eventFromResult(data)
    val api = flutterApi
    if (api != null) {
      scope.launch { api.onWindowEvent(event) }
    }
    return true
  }
}
