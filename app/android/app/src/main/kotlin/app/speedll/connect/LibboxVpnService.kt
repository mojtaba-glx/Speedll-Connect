package app.speedll.connect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SystemProxyStatus
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

class LibboxVpnService : VpnService(), CommandServerHandler {
    companion object {
        const val TAG = "SpeedllLibboxVpn"
        const val CHANNEL_ID = "speedll_libbox_vpn_channel"
        const val NOTIFICATION_ID = 1002

        const val ACTION_START = "app.speedll.connect.LIBBOX_START"
        const val ACTION_STOP = "app.speedll.connect.LIBBOX_STOP"
        const val EXTRA_CONFIG = "extra_config"
        const val EXTRA_KILL_SWITCH = "extra_kill_switch"

        @Volatile
        var isRunning: Boolean = false
            private set

        var statusCallback: ((String) -> Unit)? = null
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val stateLock = Any()
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "Speedll-LibboxWorker").apply { isDaemon = true }
    }

    private lateinit var platformInterface: LibboxPlatformInterface

    @Volatile
    private var commandServer: CommandServer? = null

    @Volatile
    private var tunInterface: ParcelFileDescriptor? = null

    @Volatile
    private var activeConfigJson: String? = null

    @Volatile
    private var stopping = true

    @Volatile
    private var foregroundStarted = false

    @Volatile
    var isKillSwitchEnabled: Boolean = false
        private set

    override fun onCreate() {
        super.onCreate()
        platformInterface = LibboxPlatformInterface(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config.isNullOrBlank()) {
                    updateStatus("failed:ERR-CORE-CONFIG")
                    stopSelf()
                    return START_NOT_STICKY
                }
                isKillSwitchEnabled = intent.getBooleanExtra(EXTRA_KILL_SWITCH, false)
                startForegroundCompat("در حال آماده‌سازی تونل...")
                execute {
                    startTunnelInternal(config)
                }
            }

            ACTION_STOP -> {
                stopTunnelAndSelf()
            }
        }

        return START_NOT_STICKY
    }

    internal fun newTunBuilder(): Builder = Builder()

    internal fun onTunEstablished(interfaceDescriptor: ParcelFileDescriptor) {
        synchronized(stateLock) {
            closeTunLocked()
            tunInterface = interfaceDescriptor
        }
        DefaultNetworkMonitor.defaultNetwork?.let { network ->
            try {
                setUnderlyingNetworks(arrayOf(network))
            } catch (e: Exception) {
                Log.w(TAG, "Could not set underlying network: ${e.javaClass.simpleName}")
            }
        }
    }

    internal fun onPhysicalNetworkChanged(network: android.net.Network?) {
        if (network == null || tunInterface == null) return
        try {
            setUnderlyingNetworks(arrayOf(network))
        } catch (e: Exception) {
            Log.w(TAG, "Could not update underlying network: ${e.javaClass.simpleName}")
        }
    }

    private fun startTunnelInternal(configJson: String) {
        synchronized(stateLock) {
            stopping = false
            cleanupResourcesLocked()
            activeConfigJson = configJson
        }

        try {
            LibboxRuntime.ensureSetup(this)

            if (VpnService.prepare(this) != null) {
                fail("ERR-VPN-PERMISSION")
                return
            }

            updateStatus("connecting")
            updateNotification("در حال راه‌اندازی هسته sing-box...")
            DefaultNetworkMonitor.start(this, this)

            val server = CommandServer(this, platformInterface)
            server.start()
            synchronized(stateLock) {
                commandServer = server
            }

            Libbox.checkConfig(configJson)
            server.startOrReloadService(
                configJson,
                OverrideOptions(),
            )

            if (stopping) {
                cleanupResources()
                return
            }
            if (tunInterface == null) {
                fail("ERR-TUN-ESTABLISH")
                return
            }

            isRunning = true
            updateStatus("connected")
            updateNotification("اتصال برقرار است")
        } catch (e: Exception) {
            Log.e(TAG, "libbox start failed: ${e.javaClass.simpleName}")
            if (stopping) {
                cleanupResources()
            } else {
                fail("ERR-CORE-START")
            }
        }
    }

    private fun fail(code: String) {
        synchronized(stateLock) {
            stopping = true
            cleanupResourcesLocked()
        }
        isRunning = false
        updateStatus("failed:$code")
        updateNotification("راه‌اندازی اتصال ناموفق بود")
        stopForegroundCompat()
        stopSelf()
    }

    private fun stopTunnelInternal(notifyDisconnected: Boolean = true) {
        synchronized(stateLock) {
            stopping = true
            cleanupResourcesLocked()
        }
        isRunning = false
        if (notifyDisconnected) {
            updateStatus("disconnected")
        }
        stopForegroundCompat()
    }

    private fun stopTunnelAndSelf() {
        execute {
            stopTunnelInternal()
            stopSelf()
        }
    }

    private fun cleanupResources() {
        synchronized(stateLock) {
            cleanupResourcesLocked()
        }
    }

    private fun cleanupResourcesLocked() {
        val server = commandServer
        commandServer = null
        if (server != null) {
            try {
                server.closeService()
            } catch (e: Exception) {
                Log.w(TAG, "Could not close libbox service: ${e.javaClass.simpleName}")
            }
        }
        closeTunLocked()
        if (server != null) {
            try {
                server.close()
            } catch (e: Exception) {
                Log.w(TAG, "Could not close command server: ${e.javaClass.simpleName}")
            }
        }
        DefaultNetworkMonitor.stop()
        activeConfigJson = null
    }

    private fun closeTunLocked() {
        val descriptor = tunInterface
        tunInterface = null
        if (descriptor != null) {
            try {
                descriptor.close()
            } catch (e: Exception) {
                Log.w(TAG, "Could not close tun interface: ${e.javaClass.simpleName}")
            }
        }
    }

    override fun serviceStop() {
        stopTunnelAndSelf()
    }

    override fun serviceReload() {
        execute {
            val config = activeConfigJson ?: return@execute
            val server = commandServer ?: return@execute
            try {
                server.startOrReloadService(
                    config,
                    OverrideOptions(),
                )
                updateStatus("connected")
                updateNotification("اتصال برقرار است")
            } catch (e: Exception) {
                Log.e(TAG, "libbox reload failed: ${e.javaClass.simpleName}")
                if (stopping) {
                    cleanupResources()
                } else {
                    fail("ERR-CORE-RELOAD")
                }
            }
        }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        return SystemProxyStatus().apply {
            available = false
            enabled = false
        }
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
    }

    override fun triggerNativeCrash() {
        if (BuildConfig.DEBUG) {
            Thread {
                throw RuntimeException("debug native crash")
            }.start()
        }
    }

    override fun writeDebugMessage(message: String?) {
        if (BuildConfig.DEBUG) {
            Log.d("SpeedllLibbox", message.orEmpty())
        }
    }

    override fun connectSSHAgent(): Int = -1

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Speedll Connect VPN",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "نمایش وضعیت سرویس فعال Speedll Connect"
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(statusText: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = Intent(this, LibboxVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Speedll Connect")
            .setContentText(statusText)
            .setSmallIcon(R.drawable.ic_stat_speedll)
            .setContentIntent(contentPendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "قطع اتصال",
                stopPendingIntent,
            )
            .setOngoing(true)
            .build()
    }

    private fun startForegroundCompat(statusText: String) {
        val notification = buildNotification(statusText)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregroundStarted = true
    }

    private fun updateNotification(statusText: String) {
        mainHandler.post {
            if (foregroundStarted) {
                getSystemService(NotificationManager::class.java)
                    ?.notify(NOTIFICATION_ID, buildNotification(statusText))
            }
        }
    }

    private fun stopForegroundCompat() {
        if (foregroundStarted) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
            foregroundStarted = false
        }
    }

    private fun updateStatus(phase: String) {
        mainHandler.post {
            statusCallback?.invoke(phase)
        }
    }

    private fun execute(block: () -> Unit) {
        try {
            worker.execute(block)
        } catch (_: RejectedExecutionException) {
        }
    }

    override fun onRevoke() {
        stopTunnelInternal()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopTunnelInternal(notifyDisconnected = !stopping)
        worker.shutdownNow()
        super.onDestroy()
    }
}
