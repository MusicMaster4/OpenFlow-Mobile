package com.jubar.voxora

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.SoundPool
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

object OpenFlowFeedback {
    private var soundPool: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val loadedIds = mutableSetOf<Int>()
    private var pendingSound: String? = null

    @Synchronized
    fun initialize(context: Context) {
        if (soundPool != null) return
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val pool = SoundPool.Builder()
            .setMaxStreams(1)
            .setAudioAttributes(attributes)
            .build()
        soundPool = pool
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status != 0) return@setOnLoadCompleteListener
            synchronized(this) {
                loadedIds.add(sampleId)
                val pending = pendingSound
                if (pending != null && soundIds[pending] == sampleId) {
                    pendingSound = null
                    playLoaded(pending)
                }
            }
        }
        soundIds["start"] = pool.load(context, R.raw.openflow_start, 1)
        soundIds["close"] = pool.load(context, R.raw.openflow_close, 1)
        soundIds["cancel"] = pool.load(context, R.raw.openflow_cancel, 1)
        soundIds["loaded"] = pool.load(context, R.raw.openflow_loaded, 1)
        soundIds["handsfree"] = pool.load(context, R.raw.openflow_handsfree, 1)
    }

    @Synchronized
    fun play(context: Context, sound: String) {
        initialize(context.applicationContext)
        vibrate(context, sound)
        val soundId = soundIds[sound] ?: return
        if (!loadedIds.contains(soundId)) {
            pendingSound = sound
            return
        }
        playLoaded(sound)
    }

    @Synchronized
    private fun playLoaded(sound: String) {
        val soundId = soundIds[sound] ?: return
        soundPool?.play(soundId, 0.72f, 0.72f, 1, 0, 1f)
    }

    private fun vibrate(context: Context, sound: String) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } ?: return
        if (!vibrator.hasVibrator()) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val effect = when (sound) {
                "cancel" -> VibrationEffect.createWaveform(
                    longArrayOf(0, 12, 34, 16),
                    intArrayOf(0, 28, 0, 38),
                    -1,
                )
                "loaded" -> VibrationEffect.createWaveform(
                    longArrayOf(0, 9, 38, 9),
                    intArrayOf(0, 24, 0, 30),
                    -1,
                )
                "start" -> VibrationEffect.createOneShot(16, 34)
                else -> VibrationEffect.createOneShot(12, 28)
            }
            vibrator.vibrate(effect)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(if (sound == "cancel") longArrayOf(0, 12, 34, 16) else longArrayOf(0, 14), -1)
        }
    }
}

object RecordingAudioSilencer {
    private const val PREFS = "openflow_recording_environment"
    private const val KEY_PENDING_RESTORE = "pending_restore"
    private const val KEY_PREVIOUS_FILTER = "previous_filter"
    private const val KEY_MUSIC_WAS_MUTED = "music_was_muted"
    private const val SILENCE_DELAY_MS = 160L

    private val handler = Handler(Looper.getMainLooper())
    private var active = false
    private var initialized = false
    private var focusRequest: AudioFocusRequest? = null
    private var legacyFocusListener: AudioManager.OnAudioFocusChangeListener? = null
    private val applySilence = Runnable { applyPendingSilence() }
    private var applicationContext: Context? = null

    @Synchronized
    fun recoverOnce(context: Context) {
        if (initialized) return
        initialized = true
        applicationContext = context.applicationContext
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(KEY_PENDING_RESTORE, false)) return
        restore(context)
    }

    @Synchronized
    fun start(context: Context) {
        applicationContext = context.applicationContext
        if (active) return
        active = true
        handler.removeCallbacks(applySilence)
        handler.postDelayed(applySilence, SILENCE_DELAY_MS)
    }

    @Synchronized
    fun stop(context: Context) {
        active = false
        handler.removeCallbacks(applySilence)
        restore(context)
    }

    @Synchronized
    private fun applyPendingSilence() {
        if (!active) return
        val context = applicationContext ?: return
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        preferences.edit()
            .putBoolean(KEY_PENDING_RESTORE, true)
            .putInt(KEY_PREVIOUS_FILTER, notifications.currentInterruptionFilter)
            .putBoolean(KEY_MUSIC_WAS_MUTED, audio.isStreamMute(AudioManager.STREAM_MUSIC))
            .apply()

        requestAudioFocus(audio)
        try {
            audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, 0)
        } catch (_: SecurityException) {
            // Audio focus still asks compatible apps to pause.
        }
        if (notifications.isNotificationPolicyAccessGranted) {
            try {
                notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
            } catch (_: SecurityException) {
                // The user can grant this optional special access from settings.
            }
        }
    }

    private fun requestAudioFocus(audio: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                .setOnAudioFocusChangeListener { }
                .build()
            focusRequest = request
            audio.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            val listener = AudioManager.OnAudioFocusChangeListener { }
            legacyFocusListener = listener
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE,
            )
        }
    }

    @Synchronized
    private fun restore(context: Context) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (preferences.getBoolean(KEY_PENDING_RESTORE, false)) {
            if (!preferences.getBoolean(KEY_MUSIC_WAS_MUTED, false)) {
                try {
                    audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)
                } catch (_: SecurityException) {
                    // Best effort; never change the numeric volume level.
                }
            }
            if (notifications.isNotificationPolicyAccessGranted) {
                val previous = preferences.getInt(
                    KEY_PREVIOUS_FILTER,
                    NotificationManager.INTERRUPTION_FILTER_ALL,
                )
                try {
                    notifications.setInterruptionFilter(previous)
                } catch (_: SecurityException) {
                    // Permission may have been revoked while recording.
                }
            }
            preferences.edit().clear().apply()
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let(audio::abandonAudioFocusRequest)
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            legacyFocusListener?.let(audio::abandonAudioFocus)
            legacyFocusListener = null
        }
    }
}
