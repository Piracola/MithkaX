package x.empty.mithka

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's UI ticks.
 *
 * The platform's own haptic effect is what exteraless fires for its interface
 * (`performHapticFeedback(LONG_PRESS, FLAG_IGNORE_GLOBAL_SETTING)`), and it is
 * the only path that produces a felt tick on every device: a raw `Vibrator`
 * waveform of a few milliseconds is dropped outright by some HALs. Both ignore
 * flags bypass the system "touch vibration" switch, so the tick still fires
 * with it off.
 *
 * A raw one-shot stays as the fallback for a refused request (unattached
 * window), and Dart falls back again when this answers false — a tick can
 * never disappear silently.
 */
class HapticsPlugin(activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {
    private val appContext = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)

    /** Manager first, legacy service after it: some ROMs ship no manager. */
    @Suppress("DEPRECATION")
    private val vibrator: Vibrator? = try {
        val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            appContext.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
        } else {
            null
        }
        val resolved = manager?.defaultVibrator
            ?: appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
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

    private fun vibrate(kind: String?): Boolean {
        val constant = when (kind) {
            "light", "selection" -> HapticFeedbackConstants.KEYBOARD_TAP
            "heavy" -> confirmConstant()
            "vibrate" -> rejectConstant()
            // medium, and anything unknown: exteraless's own interface tick.
            else -> HapticFeedbackConstants.LONG_PRESS
        }
        val fired = activity.window?.decorView?.performHapticFeedback(constant, FLAGS)
            ?: false
        return fired || oneShot(kind)
    }

    /** API 30's "positive confirmation" thump, stronger than a long press. */
    private fun confirmConstant(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.CONFIRM
        } else {
            HapticFeedbackConstants.LONG_PRESS
        }

    /** API 30's rejection buzz, for error feedback. */
    private fun rejectConstant(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            HapticFeedbackConstants.REJECT
        } else {
            HapticFeedbackConstants.LONG_PRESS
        }

    /** Only used when the platform haptic was refused; a plain buzz, no waveform. */
    @Suppress("DEPRECATION")
    private fun oneShot(kind: String?): Boolean {
        val target = vibrator ?: return false
        val durationMs = when (kind) {
            "light" -> 20L
            "selection" -> 15L
            "heavy" -> 50L
            "vibrate" -> 60L
            else -> 35L
        }
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                target.vibrate(
                    VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE),
                )
            } else {
                target.vibrate(durationMs)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "mithka/haptics"

        /** Ignore the view's own switch and the system touch-vibration one. */
        private const val FLAGS = HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING or
            HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
    }
}
