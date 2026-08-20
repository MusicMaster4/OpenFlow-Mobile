package com.jubar.voxora

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var overlayChannel: MethodChannel? = null
    private var overlayReceiver: BroadcastReceiver? = null
    private var updateChannel: MethodChannel? = null
    private var updateExecutor: ExecutorService? = null
    private lateinit var appUpdater: AppUpdater

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hideNavigationControls()
    }

    override fun onPostResume() {
        super.onPostResume()
        hideNavigationControls()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideNavigationControls()
    }

    private fun hideNavigationControls() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.navigationBars())
        }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        OpenFlowEngine.cached()

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        OpenFlowEngine.attach(this, flutterEngine)
        OpenFlowFeedback.initialize(applicationContext)
        RecordingAudioSilencer.recoverOnce(applicationContext)
        configureUpdateChannel(flutterEngine)
        overlayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            OpenFlowEngine.OVERLAY_CHANNEL,
        )

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

    private fun configureUpdateChannel(flutterEngine: FlutterEngine) {
        appUpdater = AppUpdater(applicationContext)
        appUpdater.clearIfInstalled(installedVersionCode())
        updateExecutor = Executors.newSingleThreadExecutor()
        updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL_NAME,
        )
        updateChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getAppInfo" -> result.success(appInfo())
                    "checkForUpdate" -> runUpdateTask(result) {
                        val manifest = UpdateClient.fetch(BuildConfig.UPDATE_CHANNEL)
                        if (manifest.isNewerThan(installedVersionCode())) manifest.toMap() else null
                    }
                    "downloadUpdate" -> {
                        val raw = call.arguments as? Map<*, *>
                            ?: error("The update details are missing.")
                        val manifest = AndroidUpdateManifest.fromMap(raw)
                        require(manifest.channel == BuildConfig.UPDATE_CHANNEL) {
                            "The update belongs to a different channel."
                        }
                        require(manifest.isNewerThan(installedVersionCode())) {
                            "This update is not newer than the installed app."
                        }
                        runUpdateTask(result) {
                            appUpdater.download(manifest) { received, total ->
                                runOnUiThread {
                                    updateChannel?.invokeMethod(
                                        "downloadProgress",
                                        mapOf("received" to received, "total" to total),
                                    )
                                }
                            }
                            manifest.toMap()
                        }
                    }
                    "installDownloadedUpdate" -> {
                        val pending = appUpdater.pendingManifest()
                            ?: error("No verified update is ready.")
                        require(pending.channel == BuildConfig.UPDATE_CHANNEL) {
                            "The downloaded update belongs to a different channel."
                        }
                        if (!appUpdater.canInstallPackages()) {
                            startActivity(appUpdater.requestInstallPermission())
                            result.success(mapOf("permissionRequired" to true))
                        } else {
                            appUpdater.installVerified()
                            result.success(mapOf("permissionRequired" to false))
                        }
                    }
                    "hasInstallPermission" -> result.success(appUpdater.canInstallPackages())
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error("openflow_update", error.message ?: "Update failed.", null)
            }
        }
    }

    private fun appInfo(): Map<String, Any> = mapOf(
        "versionName" to BuildConfig.VERSION_NAME,
        "versionCode" to installedVersionCode(),
        "channel" to BuildConfig.UPDATE_CHANNEL,
    )

    @Suppress("DEPRECATION")
    private fun installedVersionCode(): Long {
        val info = packageManager.getPackageInfo(packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
    }

    private fun runUpdateTask(result: MethodChannel.Result, task: () -> Any?) {
        val executor = updateExecutor ?: error("The update service is unavailable.")
        executor.execute {
            try {
                val value = task()
                runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("openflow_update", error.message ?: "Update failed.", null)
                }
            }
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
        updateChannel?.setMethodCallHandler(null)
        updateChannel = null
        updateExecutor?.shutdownNow()
        updateExecutor = null
        OpenFlowEngine.detach(this)
        super.onDestroy()
        if (!FloatingOverlayService.isRunning) {
            OpenFlowEngine.destroyIfDetached()
        }
    }

    companion object {
        private const val UPDATE_CHANNEL_NAME = "openflow/update"
    }
}
