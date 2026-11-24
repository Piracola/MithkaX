package x.empty.mithka

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's UI ticks, using the two constants the reference client uses for
 * its interface: `KEYBOARD_TAP` for taps, toggles, sliders and emoji, and
 * `LONG_PRESS` for long presses, drag lifts and destructive actions. Errors
 * get the `APP_ERROR` rhythm — two presses instead of one.
 *
 * `performHapticFeedback` is the platform's own effect, which is the only path
 * that produces a felt tick on every device (a raw `Vibrator` waveform of a
 * few milliseconds is dropped outright by some HALs). Both ignore flags bypass
 * the system "touch vibration" switch, so the tick still fires with it off.
 *
 * A raw one-shot covers a refused request (unattached window), and Dart falls
 * back again when this answers false — a tick can never disappear silently.
 */
class HapticsPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) :
    MethodChannel.MethodCallHandler {
    private val appContext = activity.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())

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
            "longPress", "error" -> HapticFeedbackConstants.LONG_PRESS
            else -> HapticFeedbackConstants.KEYBOARD_TAP
        }
        if (!tick(constant)) return oneShot(kind)
        if (kind == "error") {
            // APP_ERROR is a double buzz: the second pulse lands 150 ms later.
            handler.postDelayed(
                { tick(HapticFeedbackConstants.LONG_PRESS) },
                ERROR_GAP_MS,
            )
        }
        return true
    }

    /** The platform haptic; false only when the window cannot take it. */
    private fun tick(constant: Int): Boolean {
        val view = activity.window?.decorView ?: return false
        return view.performHapticFeedback(constant, FLAGS)
    }

    /** Only used when the platform haptic was refused; a plain buzz, no waveform. */
    @Suppress("DEPRECATION")
    private fun oneShot(kind: String?): Boolean {
        val target = vibrator ?: return false
        val durationMs = when (kind) {
            "longPress" -> 40L
            "error" -> 200L
            else -> 20L
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
        handler.removeCallbacksAndMessages(null)
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "mithka/haptics"

        /** Ignore the view's own switch and the system touch-vibration one. */
        private const val FLAGS = HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING or
            HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING

        /** Gap between the two pulses of an error buzz. */
        private const val ERROR_GAP_MS = 150L
    }
}
