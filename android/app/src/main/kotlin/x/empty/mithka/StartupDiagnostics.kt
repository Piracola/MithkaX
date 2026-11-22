package x.empty.mithka

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * TEMPORARY device-side startup trace (icon-switch cold-start investigation).
 *
 * The phone this is debugged on has no adb, so the last launch has to describe
 * itself from inside the app: [log] appends one timestamped line per event,
 * [recordCrash] keeps the uncaught-exception stack of a process that died, and
 * the Settings > Developer screen reads both back as copyable text.
 *
 * Delete this object, its channel and the view once the crash is understood.
 */
object StartupDiagnostics {
    private const val MAX_BYTES = 512 * 1024L
    private val stamp = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)
    private var tracedProcess = -1

    fun directory(context: Context): File =
        File(context.filesDir, "startup-diagnostics").apply { mkdirs() }

    fun startupFile(context: Context): File = File(directory(context), "startup.log")

    fun crashFile(context: Context): File = File(directory(context), "crash.log")

    /**
     * Marks the start of a new process WITHOUT dropping the previous one.
     *
     * A crash that aborts natively writes nothing itself, so the only record of
     * what led to it is the tail of the run that died. Truncating here threw
     * that tail away exactly when it was needed (the next launch overwrote the
     * file before it could be read), so the trace is append-only and trimmed
     * from the front once it outgrows [MAX_BYTES].
     */
    @Synchronized
    fun startProcess(context: Context) {
        val pid = android.os.Process.myPid()
        if (tracedProcess != pid) {
            tracedProcess = pid
            trimIfNeeded(context)
            log(context, "process", "start pid=$pid")
            logPreviousExits(context)
        }
    }

    /** Drops the oldest runs, keeping whole process sections. */
    private fun trimIfNeeded(context: Context) {
        val file = startupFile(context)
        if (file.length() <= MAX_BYTES) return
        try {
            val lines = file.readLines()
            val keep = lines.takeLast(MAX_BYTES.toInt() / 80)
            val from = keep.indexOfFirst { it.contains("] process: start pid=") }
            file.writeText((if (from >= 0) keep.drop(from) else keep).joinToString("\n"))
            file.appendText("\n")
        } catch (_: Throwable) {
            file.writeText("")
        }
    }

    /**
     * Android's own verdict on how the PREVIOUS processes ended — the only
     * signal that survives a native crash or an ANR, where no uncaught handler
     * ever runs (API 30+).
     */
    private fun logPreviousExits(context: Context) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) return
        try {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE)
                as android.app.ActivityManager
            val reasons = manager.getHistoricalProcessExitReasons(
                context.packageName,
                0,
                5,
            )
            for (info in reasons) {
                val trace = try {
                    info.traceInputStream?.use { input ->
                        input.readBytes().toString(Charsets.UTF_8)
                    }
                } catch (_: Throwable) {
                    null
                }
                log(
                    context,
                    "exit",
                    "ts=${info.timestamp} reason=${info.reason} " +
                        "status=${info.status} desc=${info.description}",
                )
                if (!trace.isNullOrBlank()) {
                    log(context, "exit", "trace:\n${trace.take(8000)}")
                }
            }
        } catch (error: Throwable) {
            log(context, "exit", "history unavailable: $error")
        }
    }

    @Synchronized
    fun log(context: Context, tag: String, message: String) {
        try {
            val file = startupFile(context)
            // Trim from the FRONT; wiping here would delete the very tail that
            // explains a native abort.
            if (file.length() > MAX_BYTES) trimIfNeeded(context)
            file.appendText(
                "${stamp.format(Date())} [${android.os.Process.myPid()}] " +
                    "$tag: $message\n",
            )
        } catch (_: Throwable) {
            // Diagnostics must never be the reason a launch fails.
        }
    }

    @Synchronized
    fun recordCrash(context: Context, thread: Thread, throwable: Throwable) {
        try {
            crashFile(context).appendText(
                "=== ${stamp.format(Date())} pid=${android.os.Process.myPid()} " +
                    "thread=${thread.name} ===\n" +
                    throwable.stackTraceToString() + "\n",
            )
        } catch (_: Throwable) {
        }
    }

    @Synchronized
    fun read(context: Context): Map<String, String> {
        val startup = startupFile(context)
        val crash = crashFile(context)
        return mapOf(
            "startup" to if (startup.exists()) startup.readText() else "",
            "crash" to if (crash.exists()) crash.readText() else "",
            "pid" to android.os.Process.myPid().toString(),
        )
    }

    @Synchronized
    fun clear(context: Context) {
        startupFile(context).delete()
        crashFile(context).delete()
    }
}
