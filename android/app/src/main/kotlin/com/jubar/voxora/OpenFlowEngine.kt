package com.jubar.voxora

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import android.view.accessibility.AccessibilityManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * Owns the Flutter engine used by the floating control.
 *
 * Android destroys the launcher Activity when its task is removed from Recents,
 * but the explicitly enabled foreground overlay service keeps running. Keeping
 * this engine cached lets the existing Dart controller continue recording and
 * transcribing without retaining the destroyed Activity.
 */
object OpenFlowEngine {
    const val CACHE_ID = "openflow.persistent.overlay.engine"
    const val OVERLAY_CHANNEL = "openflow/overlay"

    private var activityReference: WeakReference<Activity>? = null

    fun cached(): FlutterEngine? = FlutterEngineCache.getInstance().get(CACHE_ID)

    fun attach(activity: Activity, engine: FlutterEngine) {
        activityReference = WeakReference(activity)
        FlutterEngineCache.getInstance().put(CACHE_ID, engine)
        configureOverlayChannel(activity.applicationContext, engine)
    }

    fun detach(activity: Activity) {
        if (activityReference?.get() === activity) {
            activityReference?.clear()
            activityReference = null
        }
    }

    fun destroyIfDetached() {
        if (activityReference?.get() != null) return
        val engine = cached() ?: return
        FlutterEngineCache.getInstance().remove(CACHE_ID)
        engine.destroy()
    }

    fun dispatchOverlayAction(action: String, onComplete: (() -> Unit)? = null): Boolean {
        val engine = cached() ?: return false
        if (!engine.dartExecutor.isExecutingDart) return false
        Handler(Looper.getMainLooper()).post {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            if (onComplete == null) {
                channel.invokeMethod("overlayAction", mapOf("action" to action))
            } else {
                channel.invokeMethod(
                    "overlayAction",
                    mapOf("action" to action),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) = onComplete()

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) = onComplete()

                        override fun notImplemented() = onComplete()
                    },
                )
            }
        }
        return true
    }

    private fun configureOverlayChannel(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isOverlayGranted" -> result.success(Settings.canDrawOverlays(context))
                        "requestOverlayPermission" -> {
                            launchSettings(
                                context,
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:${context.packageName}"),
                                ),
                            )
                            result.success(null)
                        }
                        "startOverlay" -> {
                            if (!Settings.canDrawOverlays(context)) {
                                result.success(false)
                            } else {
                                FloatingOverlayService.start(context)
                                result.success(true)
                            }
                        }
                        "stopOverlay" -> {
                            FloatingOverlayService.stop(context)
                            result.success(null)
                        }
                        "isOverlayRunning" -> result.success(FloatingOverlayService.isRunning)
                        "hasRecordAudioPermission" -> result.success(
                            ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.RECORD_AUDIO,
                            ) == PackageManager.PERMISSION_GRANTED,
                        )
                        "isAccessibilityEnabled" -> result.success(
                            isOpenFlowAccessibilityEnabled(context),
                        )
                        "openAccessibilitySettings" -> {
                            launchSettings(context, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            result.success(null)
                        }
                        "openAppDetailsSettings" -> {
                            launchSettings(
                                context,
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:${context.packageName}"),
                                ),
                            )
                            result.success(null)
                        }
                        "hasNotificationPolicyAccess" -> {
                            val manager = context.getSystemService(
                                Context.NOTIFICATION_SERVICE,
                            ) as NotificationManager
                            result.success(manager.isNotificationPolicyAccessGranted)
                        }
                        "openNotificationPolicySettings" -> {
                            launchSettings(
                                context,
                                Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS),
                            )
                            result.success(null)
                        }
                        "setRecordingActive" -> {
                            val active = call.argument<Boolean>("active") == true
                            val silence = call.argument<Boolean>("silence") == true
                            activityReference?.get()?.let { activity ->
                                if (!activity.isFinishing && !activity.isDestroyed) {
                                    if (active) {
                                        activity.window.addFlags(
                                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                                        )
                                    } else {
                                        activity.window.clearFlags(
                                            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                                        )
                                    }
                                }
                            }
                            FloatingOverlayService.setKeepScreenOn(active)
                            if (active && silence) {
                                RecordingAudioSilencer.start(context)
                            } else {
                                RecordingAudioSilencer.stop(context)
                            }
                            result.success(null)
                        }
                        "playFeedback" -> {
                            OpenFlowFeedback.play(
                                context,
                                call.argument<String>("sound").orEmpty(),
                            )
                            result.success(null)
                        }
                        "copyText" -> {
                            val clipboard = context.getSystemService(
                                Context.CLIPBOARD_SERVICE,
                            ) as ClipboardManager
                            clipboard.setPrimaryClip(
                                ClipData.newPlainText(
                                    "Transcrição do OpenFlow",
                                    call.argument<String>("text").orEmpty(),
                                ),
                            )
                            result.success(true)
                        }
                        "pasteText" -> result.success(
                            OpenFlowAccessibilityService.pasteText(
                                call.argument<String>("text").orEmpty(),
                                call.argument<Boolean>("keepInClipboard") != false,
                            ),
                        )
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
    }

    private fun launchSettings(context: Context, intent: Intent) {
        val activity = activityReference?.get()
        if (activity != null && !activity.isFinishing && !activity.isDestroyed) {
            activity.startActivity(intent)
        } else {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    private fun isOpenFlowAccessibilityEnabled(context: Context): Boolean {
        val manager = context.getSystemService(
            Context.ACCESSIBILITY_SERVICE,
        ) as AccessibilityManager
        return manager
            .getEnabledAccessibilityServiceList(
                android.accessibilityservice.AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
            )
            .any { info ->
                val serviceName = info.resolveInfo.serviceInfo.name
                serviceName == OpenFlowAccessibilityService::class.java.name ||
                    serviceName.endsWith(".OpenFlowAccessibilityService")
            }
    }
}
