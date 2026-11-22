package x.empty.mithka

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

/**
 * The one FlutterEngine of this process.
 *
 * A per-Activity engine cannot survive `Back` while the process does, and a
 * process cannot host two engines: TDLib keeps its `td_receive` lock in a
 * process-wide native static, so the second engine's first receive aborts the
 * whole process
 *
 *   [Client.cpp:285] Receive must not be called simultaneously from two
 *   different threads
 *
 * Keeping the engine in the Application's lifetime removes the whole class:
 * `Back` finishes the Activity and the engine (with TDLib, its clients and its
 * receive thread) stays exactly where it is; the next launch attaches the same
 * engine to the new Activity — Flutter's `attachToActivity` detaches the old
 * one first — so the app resumes instantly instead of cold-starting a second
 * VM beside a dying one. It also makes the in-app push keep-alive service
 * meaningful: a backgrounded process still has a live TDLib to receive with.
 */
object CachedEngine {
    @Volatile
    var instance: FlutterEngine? = null
        private set

    /** True when Dart is already running in this process. */
    val isRunning: Boolean
        get() = instance?.dartExecutor?.isExecutingDart == true

    @Synchronized
    fun acquire(context: Context): FlutterEngine {
        instance?.let { return it }
        // Plugins are registered explicitly by MainActivity (it mirrors the
        // generated registry), so automatic registration must stay off.
        val engine = FlutterEngine(context.applicationContext, null, false)
        instance = engine
        return engine
    }
}
