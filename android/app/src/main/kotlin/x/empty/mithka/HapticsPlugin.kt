package x.empty.mithka

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's UI ticks, with the waveforms Telegram's own clients use
 * (`BotWebViewVibrationEffect` in exteraless's TMessagesProj).
 *
 * These are direct [Vibrator] calls, not `View.performHapticFeedback`: the
 * system "touch vibration" switch only gates the haptic-feedback path — which
 * is why the app went silent with it off — and the platform's KEYBOARD_TAP /
 * CLOCK_TICK constants are far weaker than these amplitude-controlled
 * waveforms. Each spec carries the amplitude table for devices with amplitude
 * control and a plain timing table for the rest, exactly as the reference
 * client does.
 */
class HapticsPlugin(activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val appContext = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)

    /** Resolved once per attach; a phone without a vibrator answers null. */
    @Suppress("DEPRECATION")
    private val vibrator: Vibrator? = try {
        val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (appContext.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            // VIBRATOR_SERVICE is deprecated on 31+, handled above.
            appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (resolved?.hasVibrator() == true) resolved else null
    } catch (_: Exception) {
        null
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "vibrate") {
            result.notImplemented()
            return
        }
        result.success(vibrate(call.arguments as? String))
    }

    /** Pre-Oreo has no VibrationEffect; the timed call is deprecated but legal. */
    @Suppress("DEPRECATION")
    private fun vibrate(kind: String?): Boolean {
        val target = vibrator ?: return false
        val spec = kind?.let { SPECS[it] } ?: IMPACT_LIGHT
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                target.vibrate(spec.effect(target.hasAmplitudeControl()))
            } else {
                target.vibrate(spec.fallbackTimings, -1)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    /** One waveform: amplitudes on capable hardware, durations everywhere else. */
    private class Spec(
        val timings: LongArray,
        val amplitudes: IntArray,
        val fallbackTimings: LongArray,
    ) {
        @RequiresApi(Build.VERSION_CODES.O)
        fun effect(amplitudeControl: Boolean): VibrationEffect =
            if (amplitudeControl) {
                VibrationEffect.createWaveform(timings, amplitudes, -1)
            } else {
                VibrationEffect.createWaveform(fallbackTimings, -1)
            }
    }

    companion object {
        const val CHANNEL = "mithka/haptics"

        private val IMPACT_LIGHT = Spec(longArrayOf(7), intArrayOf(65), longArrayOf(60))
        private val IMPACT_MEDIUM = Spec(longArrayOf(7), intArrayOf(145), longArrayOf(70))
        private val IMPACT_HEAVY = Spec(longArrayOf(7), intArrayOf(255), longArrayOf(80))
        private val SELECTION_CHANGE = Spec(longArrayOf(1), intArrayOf(65), longArrayOf(30))
        private val APP_ERROR = Spec(
            longArrayOf(30, 10, 150, 10),
            intArrayOf(0, 100, 0, 100),
            longArrayOf(40, 60, 40, 60, 65, 60, 40),
        )

        private val SPECS = mapOf(
            "light" to IMPACT_LIGHT,
            "medium" to IMPACT_MEDIUM,
            "heavy" to IMPACT_HEAVY,
            "selection" to SELECTION_CHANGE,
            "vibrate" to APP_ERROR,
        )
    }
}
