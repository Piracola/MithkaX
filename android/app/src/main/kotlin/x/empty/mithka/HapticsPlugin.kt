package x.empty.mithka

import android.app.Activity
import android.view.HapticFeedbackConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app's UI ticks.
 *
 * Flutter's own haptics channel calls `View.performHapticFeedback` without
 * flags, so the system "touch vibration" switch silences the whole app.
 * Passing [HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING] (and the
 * view-level one) is what keeps the tick audible with that switch off —
 * exteraless does the same. The constants are the platform's own, so the
 * strength follows the device's haptic engine instead of a hardcoded pattern.
 */
class HapticsPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "vibrate") {
            result.notImplemented()
            return
        }
        val constant = when (call.arguments as? String) {
            "light", "medium" -> HapticFeedbackConstants.KEYBOARD_TAP
            "heavy", "vibrate" -> HapticFeedbackConstants.LONG_PRESS
            "selection" -> HapticFeedbackConstants.CLOCK_TICK
            else -> HapticFeedbackConstants.KEYBOARD_TAP
        }
        val view = activity.window?.decorView
        val fired = view?.performHapticFeedback(
            constant,
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING or
                HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING,
        ) ?: false
        result.success(fired)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL = "mithka/haptics"
    }
}
