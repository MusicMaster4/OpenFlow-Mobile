package com.jubar.voxora

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
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
        showBubble()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun showBubble() {
        if (bubble != null) return
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val size = dp(64)
        val preferences = getSharedPreferences("openflow_overlay", Context.MODE_PRIVATE)
        layoutParams = WindowManager.LayoutParams(
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
        }
        bubble = FloatingWaveView(
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
            layoutParams?.flags = layoutParams?.flags?.or(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            ) ?: 0
        }
        windowManager.addView(bubble, layoutParams)
        instance = this
        pendingState?.let { snapshot ->
            bubble?.update(snapshot.state, snapshot.level, snapshot.bands)
        }
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
            y = max(dp(12), displayHeight - size - dp(24))
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

    override fun onDestroy() {
        hideRemovalTarget()
        bubble?.let { view ->
            try {
                windowManager.removeView(view)
            } catch (_: Throwable) {
                // The window may already have been removed.
            }
        }
        bubble = null
        layoutParams = null
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
    private var phase = 0.0
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
        visualState = state
        level = newLevel.coerceIn(0.0, 1.0)
        for (index in targetBands.indices) {
            targetBands[index] = (bands.getOrNull(index) ?: 0.0).coerceIn(0.0, 1.0)
        }
        postInvalidateOnAnimation()
    }

    fun showError() {
        errorUntil = System.currentTimeMillis() + 900
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
        phase += 0.075
        for (index in currentBands.indices) {
            currentBands[index] += (targetBands[index] - currentBands[index]) * 0.32
        }
        val centerX = width / 2f
        val centerY = height / 2f
        canvas.save()
        if (pressed) canvas.scale(0.94f, 0.94f, centerX, centerY)
        val radius = min(width, height) / 2f - 3f * density
        paint.style = Paint.Style.FILL
        paint.color = Color.rgb(17, 17, 16)
        canvas.drawCircle(centerX, centerY, radius, paint)

        val now = System.currentTimeMillis()
        val ringColor = when {
            now < errorUntil -> Color.rgb(239, 68, 68)
            visualState == "recording" -> Color.rgb(16, 185, 129)
            visualState == "transcribing" -> Color.rgb(245, 158, 11)
            else -> Color.rgb(69, 69, 63)
        }
        stroke.color = ringColor
        stroke.strokeWidth = if (visualState == "recording") 2.4f * density else 1.2f * density
        canvas.drawCircle(centerX, centerY, radius, stroke)

        when {
            now < errorUntil -> drawError(canvas, centerX, centerY)
            visualState == "recording" -> drawRecording(canvas, centerX, centerY)
            visualState == "transcribing" -> drawLoading(canvas, centerX, centerY)
            else -> drawIdle(canvas, centerX, centerY)
        }
        canvas.restore()
        if (visualState != "idle" || now < errorUntil) postInvalidateOnAnimation()
    }

    private fun drawIdle(canvas: Canvas, centerX: Float, centerY: Float) {
        val icon = appIcon ?: return
        val halfSize = 22f * density
        icon.setBounds(
            (centerX - halfSize).toInt(),
            (centerY - halfSize).toInt(),
            (centerX + halfSize).toInt(),
            (centerY + halfSize).toInt(),
        )
        icon.draw(canvas)
    }

    private fun drawRecording(canvas: Canvas, centerX: Float, centerY: Float) {
        val indexes = intArrayOf(0, 2, 4, 5, 6, 8, 10)
        val barWidth = 2.7f * density
        val gap = 3.2f * density
        val total = indexes.size * barWidth + (indexes.size - 1) * gap
        var x = centerX - total / 2f
        paint.color = Color.rgb(16, 185, 129)
        for (sourceIndex in indexes) {
            val band = currentBands[sourceIndex].toFloat()
            val animated = (sin(phase + sourceIndex * 0.7) + 1.0).toFloat() * 0.5f
            val height = (5f + min(1f, band * 1.4f + level.toFloat() * 0.25f) * 24f + animated * band * 3f) * density
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
    }

    private fun drawLoading(canvas: Canvas, centerX: Float, centerY: Float) {
        paint.color = Color.rgb(245, 158, 11)
        for (index in 0 until 5) {
            val x = centerX + (index - 2) * 7f * density
            val y = centerY + sin(phase * 1.8 - index * 0.85).toFloat() * 4f * density
            canvas.drawCircle(x, y, 2.1f * density, paint)
        }
    }

    private fun drawError(canvas: Canvas, centerX: Float, centerY: Float) {
        paint.color = Color.rgb(239, 68, 68)
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
