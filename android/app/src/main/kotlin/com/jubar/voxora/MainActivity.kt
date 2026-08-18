package com.jubar.voxora

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var overlayChannel: MethodChannel? = null
    private var overlayReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        overlayChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        overlayChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isOverlayGranted" -> result.success(Settings.canDrawOverlays(this))
                    "requestOverlayPermission" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    "startOverlay" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            result.success(false)
                        } else {
                            FloatingOverlayService.start(this)
                            result.success(true)
                        }
                    }
                    "stopOverlay" -> {
                        FloatingOverlayService.stop(this)
                        result.success(null)
                    }
                    "isOverlayRunning" -> result.success(FloatingOverlayService.isRunning)
                    "isAccessibilityEnabled" -> result.success(isOpenFlowAccessibilityEnabled())
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "pasteText" -> {
                        val text = call.argument<String>("text").orEmpty()
                        result.success(OpenFlowAccessibilityService.pasteText(text))
                    }
                    "updateOverlay" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        val level = call.argument<Number>("level")?.toDouble() ?: 0.0
                        val bands = call.argument<List<Number>>("bands")
                            ?.map { it.toDouble() }
                            ?.toDoubleArray()
                            ?: DoubleArray(11)
                        FloatingOverlayService.update(state, level, bands)
                        result.success(null)
                    }
                    "showOverlayError" -> {
                        FloatingOverlayService.showError()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("openflow_overlay", error.message, null)
            }
        }

        overlayReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.getStringExtra(FloatingOverlayService.EXTRA_EVENT) ?: return
                overlayChannel?.invokeMethod("overlayAction", mapOf("action" to action))
            }
        }
        val filter = IntentFilter(FloatingOverlayService.ACTION_OVERLAY_EVENT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(overlayReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(overlayReceiver, filter)
        }
    }

    private fun isOpenFlowAccessibilityEnabled(): Boolean {
        val manager = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager
            .getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
            .any { info ->
                val serviceName = info.resolveInfo.serviceInfo.name
                serviceName == OpenFlowAccessibilityService::class.java.name ||
                    serviceName.endsWith(".OpenFlowAccessibilityService")
            }
    }

    override fun onDestroy() {
        overlayReceiver?.let { receiver ->
            try {
                unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // Receiver was already removed by Android.
            }
        }
        overlayReceiver = null
        overlayChannel = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_NAME = "openflow/overlay"
    }
}
