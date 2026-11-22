package x.empty.mithka

import android.app.Application

/**
 * TEMPORARY: records uncaught exceptions (which is how a Kotlin/Java crash on
 * the loading page reaches the user as a silent exit) before the system kills
 * the process, and starts a fresh startup trace per process.
 *
 * Remove together with [StartupDiagnostics] once the icon-switch cold-start
 * crash is understood.
 */
class MithkaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        StartupDiagnostics.startProcess(this)
        StartupDiagnostics.log(this, "app", "Application.onCreate")
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            StartupDiagnostics.recordCrash(this, thread, throwable)
            previous?.uncaughtException(thread, throwable)
        }
    }
}
