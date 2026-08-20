package com.jubar.voxora

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings
import android.view.GestureDetector
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import androidx.core.content.ContextCompat
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class FloatingOverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private var bubble: FloatingWaveView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var removalTarget: RemovalTargetView? = null
    private var removalTargetParams: WindowManager.LayoutParams? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        instance = this
        createNotificationChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        if (!showBubble()) stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!Settings.canDrawOverlays(this) || !showBubble()) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Saved overlay coordinates are absolute pixels. Rotation, display scaling,
        // split screen and foldable posture changes can otherwise leave the bubble
        // outside the new display bounds indefinitely.
        bubble?.post { ensureBubbleOnScreen() }
    }

    private fun showBubble(): Boolean {
        // addView() registers the window synchronously, but View attachment happens
        // later. Using isAttachedToWindow here creates a race where onStartCommand
        // adds a second window immediately after onCreate added the first one.
        if (bubble != null) {
            return ensureBubbleOnScreen()
        }
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val size = dp(58)
        val preferences = getSharedPreferences("openflow_overlay", Context.MODE_PRIVATE)
        val newLayoutParams = WindowManager.LayoutParams(
            size,
            size,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = preferences.getInt("x", resources.displayMetrics.widthPixels - size - dp(18))
            y = preferences.getInt("y", dp(180))
            clampToDisplay(this)
        }
        val newBubble = FloatingWaveView(
            this,
            onDragStarted = { showRemovalTarget() },
            onMove = { deltaX, deltaY ->
                moveBubble(deltaX, deltaY)
                updateRemovalTarget()
            },
            onMoveFinished = { cancelled ->
                if (!cancelled && isBubbleInsideRemovalTarget()) {
                    removeBubbleUntilNextOpen()
                } else {
                    hideRemovalTarget()
                    savePosition()
                }
            },
            onAction = { event ->
                sendOverlayEvent(event)
            },
        )
        if (pendingKeepScreenOn) {
            newLayoutParams.flags = newLayoutParams.flags or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        }
        try {
            windowManager.addView(newBubble, newLayoutParams)
        } catch (_: RuntimeException) {
            return false
        }
        // These references represent ownership of exactly one registered window.
        // They are only published after addView succeeds.
        bubble = newBubble
        layoutParams = newLayoutParams
        savePosition()
        pendingState?.let { snapshot ->
            bubble?.update(snapshot.state, snapshot.level, snapshot.bands)
        }
        return true
    }

    private fun moveBubble(deltaX: Int, deltaY: Int) {
        val params = layoutParams ?: return
        val view = bubble ?: return
        val maxX = max(0, resources.displayMetrics.widthPixels - params.width)
        val maxY = max(0, resources.displayMetrics.heightPixels - params.height)
        params.x = (params.x + deltaX).coerceIn(0, maxX)
        params.y = (params.y + deltaY).coerceIn(0, maxY)
        windowManager.updateViewLayout(view, params)
    }

    private fun savePosition() {
        val params = layoutParams ?: return
        getSharedPreferences("openflow_overlay", Context.MODE_PRIVATE)
            .edit()
            .putInt("x", params.x)
            .putInt("y", params.y)
            .apply()
    }

    private fun ensureBubbleOnScreen(): Boolean {
        val params = layoutParams ?: return false
        val view = bubble ?: return false
        val moved = clampToDisplay(params)
        if (!moved) return true
        try {
            windowManager.updateViewLayout(view, params)
            savePosition()
            return true
        } catch (_: RuntimeException) {
            // The WindowManager may have detached the old view during a display
            // transition. Explicitly unregister it before creating a replacement,
            // so a stale window can never be left behind on screen.
            removeBubbleView()
            return showBubble()
        }
    }

    private fun removeBubbleView() {
        val view = bubble
        // Clear ownership before asking WindowManager to remove the view. This
        // keeps callbacks and repeated stop/start requests idempotent.
        bubble = null
        layoutParams = null
        if (view == null) return
        try {
            windowManager.removeViewImmediate(view)
        } catch (_: RuntimeException) {
            // The window was already removed by Android.
        }
    }

    private fun clampToDisplay(params: WindowManager.LayoutParams): Boolean {
        val width: Int
        val height: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.currentWindowMetrics.bounds
            width = bounds.width()
            height = bounds.height()
        } else {
            @Suppress("DEPRECATION")
            val metrics = resources.displayMetrics
            width = metrics.widthPixels
            height = metrics.heightPixels
        }
        val oldPosition = OverlayPosition(params.x, params.y)
        val position = clampOverlayPosition(
            position = oldPosition,
            overlayWidth = params.width,
            overlayHeight = params.height,
            displayWidth = width,
            displayHeight = height,
        )
        params.x = position.x
        params.y = position.y
        return position != oldPosition
    }

    private fun sendOverlayEvent(event: String, onDelivered: (() -> Unit)? = null) {
        if (OpenFlowEngine.dispatchOverlayAction(event, onDelivered)) return
        sendBroadcast(
            Intent(ACTION_OVERLAY_EVENT)
                .setPackage(packageName)
                .putExtra(EXTRA_EVENT, event),
        )
        onDelivered?.invoke()
    }

    private fun updateBubble(state: String, level: Double, bands: DoubleArray) {
        bubble?.update(state, level, bands)
    }

    private fun showRemovalTarget() {
        if (removalTarget != null) return
        val size = dp(96)
        val displayWidth = resources.displayMetrics.widthPixels
        val displayHeight = resources.displayMetrics.heightPixels
        removalTargetParams = WindowManager.LayoutParams(
            size,
            size,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (displayWidth - size) / 2
            // Keep the target clear of Android's gesture/three-button navigation.
            // This places it visually above Home instead of on top of the system bar.
            y = max(dp(12), displayHeight - size - navigationBarHeight() - dp(16))
        }
        removalTarget = RemovalTargetView(this)
        windowManager.addView(removalTarget, removalTargetParams)
        updateRemovalTarget()
    }

    private fun updateRemovalTarget() {
        removalTarget?.setHighlighted(isBubbleInsideRemovalTarget())
    }

    private fun isBubbleInsideRemovalTarget(): Boolean {
        val bubbleParams = layoutParams ?: return false
        val targetParams = removalTargetParams ?: return false
        val bubbleCenterX = bubbleParams.x + bubbleParams.width / 2f
        val bubbleCenterY = bubbleParams.y + bubbleParams.height / 2f
        val targetCenterX = targetParams.x + targetParams.width / 2f
        val targetCenterY = targetParams.y + targetParams.height / 2f
        val radius = targetParams.width * 0.46f
        val deltaX = bubbleCenterX - targetCenterX
        val deltaY = bubbleCenterY - targetCenterY
        return deltaX * deltaX + deltaY * deltaY <= radius * radius
    }

    private fun removeBubbleUntilNextOpen() {
        OpenFlowFeedback.play(applicationContext, "close")
        sendOverlayEvent("dismiss") {
            hideRemovalTarget()
            stopSelf()
        }
    }

    private fun hideRemovalTarget() {
        removalTarget?.let { view ->
            try {
                windowManager.removeView(view)
            } catch (_: Throwable) {
                // The target may already have been removed with the service window.
            }
        }
        removalTarget = null
        removalTargetParams = null
    }

    private fun updateKeepScreenOn(active: Boolean) {
        val params = layoutParams ?: return
        val view = bubble ?: return
        params.flags = if (active) {
            params.flags or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        } else {
            params.flags and WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON.inv()
        }
        windowManager.updateViewLayout(view, params)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL,
            "Círculo flutuante do OpenFlow",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Mantém o controle de ditado disponível sobre outros apps."
            setShowBadge(false)
        }
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("OpenFlow")
            .setContentText("Círculo flutuante ativo")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun navigationBarHeight(): Int {
        val resourceId = resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else dp(48)
    }

    override fun onDestroy() {
        hideRemovalTarget()
        removeBubbleView()
        if (instance === this) instance = null
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
        OpenFlowEngine.destroyIfDetached()
    }

    companion object {
        const val ACTION_OVERLAY_EVENT = "com.jubar.voxora.OVERLAY_EVENT"
        const val EXTRA_EVENT = "event"
        const val ACTION_STOP = "com.jubar.voxora.STOP_OVERLAY"
        private const val NOTIFICATION_CHANNEL = "openflow_floating_overlay"
        private const val NOTIFICATION_ID = 4102

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        private var instance: FloatingOverlayService? = null
        private var pendingState: OverlaySnapshot? = null
        private var pendingKeepScreenOn = false

        fun start(context: Context) {
            val intent = Intent(context, FloatingOverlayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, FloatingOverlayService::class.java))
        }

        // A non-null bubble means this service owns a WindowManager registration.
        // Attachment is asynchronous and must not be used to decide whether a
        // replacement window should be created.
        fun isBubbleVisible(): Boolean = instance?.bubble != null

        fun update(state: String, level: Double, bands: DoubleArray) {
            val snapshot = OverlaySnapshot(state, level, bands.copyOf())
            pendingState = snapshot
            instance?.updateBubble(snapshot.state, snapshot.level, snapshot.bands)
        }

        fun showError() {
            instance?.bubble?.showError()
        }

        fun setKeepScreenOn(active: Boolean) {
            pendingKeepScreenOn = active
            instance?.updateKeepScreenOn(active)
        }
    }
}

internal data class OverlayPosition(val x: Int, val y: Int)

internal fun clampOverlayPosition(
    position: OverlayPosition,
    overlayWidth: Int,
    overlayHeight: Int,
    displayWidth: Int,
    displayHeight: Int,
): OverlayPosition = OverlayPosition(
    x = position.x.coerceIn(0, max(0, displayWidth - overlayWidth)),
    y = position.y.coerceIn(0, max(0, displayHeight - overlayHeight)),
)

private data class OverlaySnapshot(
    val state: String,
    val level: Double,
    val bands: DoubleArray,
)

private class FloatingWaveView(
    context: Context,
    private val onDragStarted: () -> Unit,
    private val onMove: (Int, Int) -> Unit,
    private val onMoveFinished: (Boolean) -> Unit,
    private val onAction: (String) -> Unit,
) : View(context) {
    private val density = resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val appIcon = ContextCompat.getDrawable(context, R.mipmap.ic_launcher)?.mutate()
    private val targetBands = DoubleArray(11)
    private val currentBands = DoubleArray(11)
    private var visualState = "idle"
    private var level = 0.0
    private var displayedLevel = 0f
    private val animationStartedAt = SystemClock.uptimeMillis()
    private var lastFrameAt = animationStartedAt
    private var stateChangedAt = animationStartedAt
    private var errorUntil = 0L
    private var downRawX = 0f
    private var downRawY = 0f
    private var lastRawX = 0f
    private var lastRawY = 0f
    private var dragged = false
    private var pressed = false

    private val gestures = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(event: MotionEvent): Boolean = true

            override fun onSingleTapConfirmed(event: MotionEvent): Boolean {
                if (!dragged) onAction("toggle")
                return true
            }

            override fun onDoubleTap(event: MotionEvent): Boolean {
                if (!dragged && visualState == "recording") onAction("cancel")
                return true
            }

        },
    )

    init {
        contentDescription = "Controle flutuante do OpenFlow"
    }

    fun update(state: String, newLevel: Double, bands: DoubleArray) {
        if (state != visualState) {
            stateChangedAt = SystemClock.uptimeMillis()
        }
        visualState = state
        level = newLevel.coerceIn(0.0, 1.0)
        for (index in targetBands.indices) {
            targetBands[index] = (bands.getOrNull(index) ?: 0.0).coerceIn(0.0, 1.0)
        }
        postInvalidateOnAnimation()
    }

    fun showError() {
        errorUntil = SystemClock.uptimeMillis() + 900
        postInvalidateOnAnimation()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downRawX = event.rawX
                downRawY = event.rawY
                lastRawX = event.rawX
                lastRawY = event.rawY
                dragged = false
                pressed = true
                postInvalidateOnAnimation()
            }
            MotionEvent.ACTION_MOVE -> {
                if (!dragged &&
                    (abs(event.rawX - downRawX) > touchSlop ||
                        abs(event.rawY - downRawY) > touchSlop)
                ) {
                    dragged = true
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                    onDragStarted()
                }
                if (dragged) {
                    pressed = false
                    onMove((event.rawX - lastRawX).toInt(), (event.rawY - lastRawY).toInt())
                    lastRawX = event.rawX
                    lastRawY = event.rawY
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                pressed = false
                if (dragged) onMoveFinished(event.actionMasked == MotionEvent.ACTION_CANCEL)
                postInvalidateOnAnimation()
            }
        }
        gestures.onTouchEvent(event)
        return true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val now = SystemClock.uptimeMillis()
        val deltaSeconds = ((now - lastFrameAt).coerceIn(1L, 48L) / 1000f)
        lastFrameAt = now
        val smoothing = 1f - exp((-deltaSeconds * 12f).toDouble()).toFloat()
        for (index in currentBands.indices) {
            currentBands[index] += (targetBands[index] - currentBands[index]) * smoothing
        }
        displayedLevel += (level.toFloat() - displayedLevel) * smoothing
        val phase = (now - animationStartedAt) / 1000.0
        val stateProgress = ((now - stateChangedAt) / 240f).coerceIn(0f, 1f)
        val stateEase = 1f - (1f - stateProgress) * (1f - stateProgress) * (1f - stateProgress)
        val centerX = width / 2f
        val centerY = height / 2f
        canvas.save()
        val pressScale = if (pressed) 0.94f else 1f
        canvas.scale(pressScale, pressScale, centerX, centerY)
        val radius = min(width, height) / 2f - 3f * density
        paint.style = Paint.Style.FILL
        paint.color = Color.rgb(17, 17, 16)
        paint.alpha = 255
        canvas.drawCircle(centerX, centerY, radius, paint)

        val ringColor = when {
            now < errorUntil -> Color.rgb(239, 68, 68)
            visualState == "recording" -> Color.rgb(239, 68, 68)
            visualState == "transcribing" -> Color.rgb(234, 234, 234)
            else -> Color.rgb(69, 69, 63)
        }
        stroke.color = ringColor
        stroke.alpha = 255
        stroke.strokeWidth = if (visualState == "recording") 2.2f * density else 1.2f * density
        canvas.drawCircle(centerX, centerY, radius, stroke)

        if (visualState == "recording" || visualState == "transcribing") {
            val pulse = (
                (sin(phase * if (visualState == "recording") 4.4 else 3.1) + 1.0) * 0.5
            ).toFloat()
            stroke.alpha = (34 + pulse * 46).toInt()
            stroke.strokeWidth = (1.2f + pulse * 0.9f) * density
            canvas.drawCircle(centerX, centerY, radius - 3.2f * density + pulse * density, stroke)
            stroke.alpha = 255
        }

        canvas.save()
        canvas.scale(0.82f + stateEase * 0.18f, 0.82f + stateEase * 0.18f, centerX, centerY)
        when {
            now < errorUntil -> drawError(canvas, centerX, centerY)
            visualState == "recording" -> drawRecording(canvas, centerX, centerY, phase)
            visualState == "transcribing" -> drawLoading(canvas, centerX, centerY, phase)
            else -> drawIdle(canvas, centerX, centerY)
        }
        canvas.restore()
        if (visualState == "recording" && now >= errorUntil) {
            val pulse = ((sin(phase * 8.0) + 1.0) * 0.5).toFloat()
            paint.color = Color.rgb(239, 68, 68)
            paint.alpha = (110 + pulse * 145f).toInt()
            canvas.drawCircle(
                centerX,
                centerY - radius + 11.5f * density,
                (2.6f + pulse * 0.7f) * density,
                paint,
            )
            paint.alpha = 255
        }
        canvas.restore()
        if (visualState != "idle" || now < errorUntil || stateProgress < 1f) {
            postInvalidateOnAnimation()
        }
    }

    private fun drawIdle(canvas: Canvas, centerX: Float, centerY: Float) {
        val icon = appIcon ?: return
        val halfSize = 19.5f * density
        icon.setBounds(
            (centerX - halfSize).toInt(),
            (centerY - halfSize).toInt(),
            (centerX + halfSize).toInt(),
            (centerY + halfSize).toInt(),
        )
        icon.draw(canvas)
    }

    private fun drawRecording(canvas: Canvas, centerX: Float, centerY: Float, phase: Double) {
        val indexes = intArrayOf(0, 2, 4, 5, 6, 8, 10)
        val barWidth = 2.5f * density
        val gap = 2.8f * density
        val total = indexes.size * barWidth + (indexes.size - 1) * gap
        var x = centerX - total / 2f
        paint.color = Color.rgb(32, 32, 29)
        paint.alpha = 88
        canvas.drawRoundRect(
            centerX - 21.5f * density,
            centerY - 14f * density,
            centerX + 21.5f * density,
            centerY + 14f * density,
            14f * density,
            14f * density,
            paint,
        )
        paint.color = Color.rgb(234, 234, 234)
        for ((barIndex, sourceIndex) in indexes.withIndex()) {
            val band = currentBands[sourceIndex].toFloat()
            val breathing = ((sin(phase * 5.2 + sourceIndex * 0.74) + 1.0) * 0.5).toFloat()
            val centerWeight = 1f - abs(barIndex - 3) * 0.08f
            val energy = min(1f, band * 1.35f + displayedLevel * 0.34f)
            val height = (5f + energy * 19f * centerWeight + breathing * (2.2f + energy * 2.6f)) * density
            paint.alpha = (172 + energy * 83f).toInt()
            canvas.drawRoundRect(
                x,
                centerY - height / 2f,
                x + barWidth,
                centerY + height / 2f,
                barWidth,
                barWidth,
                paint,
            )
            x += barWidth + gap
        }
        paint.alpha = 255
    }

    private fun drawLoading(canvas: Canvas, centerX: Float, centerY: Float, phase: Double) {
        paint.color = Color.rgb(32, 32, 29)
        paint.alpha = 72
        canvas.drawRoundRect(
            centerX - 21f * density,
            centerY - 10.5f * density,
            centerX + 21f * density,
            centerY + 10.5f * density,
            10.5f * density,
            10.5f * density,
            paint,
        )
        paint.color = Color.rgb(234, 234, 234)
        for (index in 0 until 5) {
            val wave = ((sin(phase * 5.1 - index * 0.82) + 1.0) * 0.5).toFloat()
            val x = centerX + (index - 2) * 7.2f * density
            val y = centerY + (wave - 0.5f) * 5.2f * density
            val dotRadius = (1.65f + wave * 1.05f) * density
            paint.alpha = (105 + wave * 150f).toInt()
            canvas.drawCircle(x, y, dotRadius, paint)
        }
        paint.alpha = 255
    }

    private fun drawError(canvas: Canvas, centerX: Float, centerY: Float) {
        paint.color = Color.rgb(239, 68, 68)
        paint.alpha = 255
        canvas.drawRoundRect(
            centerX - 2f * density,
            centerY - 11f * density,
            centerX + 2f * density,
            centerY + 4f * density,
            2f * density,
            2f * density,
            paint,
        )
        canvas.drawCircle(centerX, centerY + 10f * density, 2.2f * density, paint)
    }
}

private class RemovalTargetView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(32, 32, 29)
        setShadowLayer(12f * density, 0f, 4f * density, 0x88000000.toInt())
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 2f * density
        color = Color.rgb(248, 113, 113)
    }
    private val crossPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(248, 113, 113)
        style = Paint.Style.STROKE
        strokeWidth = 4f * density
        strokeCap = Paint.Cap.ROUND
    }
    private var highlighted = false

    init {
        contentDescription = "Remover círculo flutuante até abrir o OpenFlow novamente"
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun setHighlighted(value: Boolean) {
        if (highlighted == value) return
        highlighted = value
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val centerX = width / 2f
        val centerY = height / 2f
        val radius = if (highlighted) 43f * density else 36f * density
        backgroundPaint.color = if (highlighted) {
            Color.rgb(127, 29, 29)
        } else {
            Color.rgb(32, 32, 29)
        }
        borderPaint.strokeWidth = if (highlighted) 3f * density else 2f * density
        canvas.drawCircle(centerX, centerY, radius, backgroundPaint)
        canvas.drawCircle(centerX, centerY, radius, borderPaint)
        val crossRadius = if (highlighted) 14f * density else 12f * density
        canvas.drawLine(
            centerX - crossRadius,
            centerY - crossRadius,
            centerX + crossRadius,
            centerY + crossRadius,
            crossPaint,
        )
        canvas.drawLine(
            centerX + crossRadius,
            centerY - crossRadius,
            centerX - crossRadius,
            centerY + crossRadius,
            crossPaint,
        )
    }
}
