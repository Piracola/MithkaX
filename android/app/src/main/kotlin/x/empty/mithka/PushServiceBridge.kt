package x.empty.mithka

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The `mithka/push` bridge: applies the selected transport, starts/stops the
 * in-app keep-alive service, exposes the UnifiedPush registration to Dart, and
 * forwards delivered payloads into the running Flutter engine.
 */
class PushServiceBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
        current = this
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = activity.applicationContext
        when (call.method) {
            "applyPushService" -> {
                val arguments = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                applyPushService(
                    context,
                    (arguments["mode"] as? Number)?.toInt()
                        ?: PushServiceStore.MODE_FCM,
                    arguments["gateway"] as? String
                        ?: PushServiceStore.DEFAULT_GATEWAY,
                    arguments["resident"] as? Boolean ?: false,
                )
                result.success(status(context))
            }

            "getUnifiedPushRegistration" -> {
                result.success(UnifiedPushManager.registration(context))
            }

            "unregisterUnifiedPush" -> {
                UnifiedPushManager.unregister(context)
                result.success(null)
            }

            "setKeepAlive" -> {
                val enabled = (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean
                    ?: false
                PushServiceStore.setKeepAliveFallback(context, enabled)
                if (enabled || PushServiceStore.mode(context) == PushServiceStore.MODE_IN_APP) {
                    PushKeepAliveService.start(context)
                } else {
                    PushKeepAliveService.stop(context)
                }
                result.success(status(context))
            }

            "getPushStatus" -> result.success(status(context))

            "getPushDiagnostics" -> {
                Thread {
                    val data = diagnostics(context)
                    mainHandler.post { result.success(data) }
                }.start()
            }

            "consumeNotificationTap" -> {
                result.success(mapOf("payload" to PushServiceStore.takePendingTap(context)))
            }

            "clearFallbackNotifications" -> {
                PushFallbackNotifier.clear(context)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (current === this) current = null
    }

    private fun applyPushService(
        context: Context,
        mode: Int,
        gateway: String,
        resident: Boolean,
    ) {
        PushServiceStore.setMode(context, mode)
        PushServiceStore.setGateway(context, gateway)
        PushServiceStore.setResident(context, resident)
        when (mode) {
            PushServiceStore.MODE_IN_APP -> {
                UnifiedPushManager.unregister(context)
                PushServiceStore.setKeepAliveFallback(context, false)
                PushKeepAliveService.start(context)
            }

            PushServiceStore.MODE_UNIFIED -> {
                PushServiceStore.setKeepAliveFallback(context, false)
                PushKeepAliveService.stop(context)
                UnifiedPushManager.register(context)
            }

            else -> {
                UnifiedPushManager.unregister(context)
                if (PushServiceStore.keepAliveFallback(context)) {
                    PushKeepAliveService.start(context)
                } else {
                    PushKeepAliveService.stop(context)
                }
            }
        }
    }

    private fun status(context: Context): Map<String, Any?> {
        val mode = PushServiceStore.mode(context)
        val registration = UnifiedPushManager.registration(context)
        return mapOf(
            "mode" to mode,
            "resident" to PushServiceStore.resident(context),
            "distributors" to UnifiedPushManager.distributors(context),
            "distributor" to (
                registration?.get("distributor")
                    ?: UnifiedPushManager.currentDistributor(context)?.let {
                        UnifiedPushManager.distributorLabel(context, it)
                    }
                ),
            "endpoint" to registration?.get("endpoint"),
            "registered" to (registration != null && mode == PushServiceStore.MODE_UNIFIED),
            "keepAlive" to PushServiceStore.keepAliveEnabled(context),
            "error" to UnifiedPushManager.error(context),
        )
    }

    /**
     * One-shot, copyable snapshot for device-side push debugging. It must never
     * include tokens, endpoints or API keys: the report is pasted into chats.
     */
    private fun diagnostics(context: Context): Map<String, Any?> {
        val notificationManager = context.getSystemService(NotificationManager::class.java)
        val activeNotifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            notificationManager.activeNotifications.map { notification ->
                mapOf(
                    "id" to notification.id,
                    "channel" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        notification.notification.channelId
                    } else {
                        null
                    },
                    "ongoing" to notification.isOngoing,
                )
            }
        } else {
            emptyList<Map<String, Any?>>()
        }
        val channels = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            listOf("mithka_push_keepalive", "mithka_push_keepalive_quiet")
                .mapNotNull { id ->
                    notificationManager.getNotificationChannel(id)?.let { channel ->
                        id to mapOf(
                            "name" to channel.name?.toString(),
                            "importance" to channel.importance,
                        )
                    }
                }
                .toMap()
        } else {
            emptyMap<String, Map<String, Any?>>()
        }
        val googleAppId = runCatching {
            val resId = context.resources.getIdentifier(
                "google_app_id",
                "string",
                context.packageName,
            )
            if (resId == 0) null else context.getString(resId)
        }.getOrNull()
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "sdkInt" to Build.VERSION.SDK_INT,
            "release" to Build.VERSION.RELEASE,
            "push" to mapOf(
                "mode" to PushServiceStore.mode(context),
                "resident" to PushServiceStore.resident(context),
                "keepAliveFallback" to PushServiceStore.keepAliveFallback(context),
                "keepAliveEnabled" to PushServiceStore.keepAliveEnabled(context),
                "gatewayHost" to runCatching {
                    java.net.URI(PushServiceStore.gateway(context)).host
                }.getOrNull(),
            ),
            "keepAliveService" to mapOf(
                "running" to PushKeepAliveService.isRunning,
                "foreground" to PushKeepAliveService.isForeground,
            ),
            "notifications" to mapOf(
                "enabled" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
                "permission" to (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        ContextCompat.checkSelfPermission(
                            context,
                            Manifest.permission.POST_NOTIFICATIONS,
                        ) == PackageManager.PERMISSION_GRANTED
                    ),
                "active" to activeNotifications,
                "channels" to channels,
            ),
            "gms" to packageDetails(context, "com.google.android.gms"),
            "gmsAvailability" to gmsAvailability(context),
            "firebase" to firebaseInfo(context),
            "googleAppIdResource" to googleAppId?.take(12),
            "unifiedPush" to mapOf(
                "distributors" to UnifiedPushManager.distributors(context),
                "error" to UnifiedPushManager.error(context),
            ),
        )
    }

    private fun packageDetails(context: Context, packageName: String): Map<String, Any?> =
        try {
            val info = context.packageManager.getPackageInfo(packageName, 0)
            mapOf(
                "installed" to true,
                "versionName" to info.versionName,
                "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    info.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    info.versionCode.toLong()
                },
                "enabled" to info.applicationInfo?.enabled,
            )
        } catch (_: PackageManager.NameNotFoundException) {
            mapOf("installed" to false)
        } catch (error: Throwable) {
            mapOf("installed" to false, "error" to error.javaClass.simpleName)
        }

    private fun gmsAvailability(context: Context): Any? =
        try {
            val clazz = Class.forName("com.google.android.gms.common.GoogleApiAvailability")
            val instance = clazz.getMethod("getInstance").invoke(null)
            clazz.getMethod("isGooglePlayServicesAvailable", Context::class.java)
                .invoke(instance, context)
        } catch (error: Throwable) {
            "${error.javaClass.simpleName}: ${error.message}"
        }

    private fun firebaseInfo(context: Context): Any? =
        try {
            val clazz = Class.forName("com.google.firebase.FirebaseApp")
            val apps = clazz.getMethod("getApps", Context::class.java)
                .invoke(null, context) as? List<*>
            apps?.map { app ->
                val options = clazz.getMethod("getOptions").invoke(app)
                val optionsClass = options?.javaClass
                mapOf(
                    "name" to clazz.getMethod("getName").invoke(app),
                    "projectId" to runCatching {
                        optionsClass?.getMethod("getProjectId")?.invoke(options)
                    }.getOrNull(),
                    "applicationId" to runCatching {
                        optionsClass?.getMethod("getApplicationId")?.invoke(options)
                    }.getOrNull(),
                )
            } ?: emptyList<Map<String, Any?>>()
        } catch (error: Throwable) {
            mapOf("error" to "${error.javaClass.simpleName}: ${error.message}")
        }

    companion object {
        const val CHANNEL = "mithka/push"
        private const val TAG = "MithkaPush"

        @Volatile
        private var current: PushServiceBridge? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        fun isEngineAttached(): Boolean = current != null

        private fun onMain(block: () -> Unit) {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                block()
            } else {
                mainHandler.post(block)
            }
        }

        fun deliverRegistration() {
            onMain {
                val bridge = current ?: return@onMain
                val context = bridge.activity.applicationContext
                bridge.channel.invokeMethod(
                    "unifiedPushRegistration",
                    UnifiedPushManager.registration(context),
                )
                bridge.channel.invokeMethod("pushStatus", bridge.status(context))
            }
        }

        fun deliverPayload(payload: String) {
            onMain {
                val bridge = current
                if (bridge == null) {
                    Log.d(TAG, "Dropping push payload: Flutter engine is not attached")
                    return@onMain
                }
                bridge.channel.invokeMethod("pushPayload", payload)
            }
        }

        fun deliverWake() {
            onMain { current?.channel?.invokeMethod("pushWake", null) }
        }

        /** Captures a UnifiedPush fallback notification tap for Dart. */
        fun captureTap(context: Context, intent: Intent?) {
            val target = intent ?: return
            val payload = target.getStringExtra(EXTRA_TAP_PAYLOAD) ?: return
            if (payload.isEmpty()) return
            if (current == null) {
                // The engine is not up yet (cold start): keep the tap for Dart's
                // first registration pass instead of dropping it.
                PushServiceStore.setPendingTap(context.applicationContext, payload)
            } else {
                onMain {
                    current?.channel?.invokeMethod("notificationTap", payload)
                }
            }
            target.removeExtra(EXTRA_TAP_PAYLOAD)
        }

        const val EXTRA_TAP_PAYLOAD = "mithka.push.tap_payload"
    }
}
