package app.speedll.connect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.Network
import android.net.TrafficStats
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
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
        const val EXTRA_SERVER_LABEL = "extra_server_label"
        const val EVENT_DNS_CLEARED = "event:dns_cleared"

        private const val NETWORK_RESET_DEBOUNCE_MS = 300L
        private const val TRANSITION_WAKE_LOCK_MS = 4000L
        private const val STICKY_PREFS_NAME = "SpeedllStickyTunnelState"
        private const val KEY_STICKY_CONFIG = "sticky_config_json"
        private const val KEY_STICKY_KILL_SWITCH = "sticky_kill_switch"
        private const val TILE_PREFS_NAME = "SpeedllQuickTileState"
        private const val KEY_TILE_CONFIG = "tile_config_json"
        private const val KEY_TILE_KILL_SWITCH = "tile_kill_switch"
        private const val KEY_TILE_LABEL = "tile_server_label"

        data class QuickTileConfig(
            val configJson: String,
            val killSwitch: Boolean,
            val serverLabel: String?,
        )

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var activeServerLabel: String? = null
            private set

        @Volatile
        var tunnelSessionId: Long = 0L
            private set

        @Volatile
        var connectedAtElapsedMs: Long = 0L
            private set

        @Volatile
        var sessionStartRxBytes: Long = 0L
            private set

        @Volatile
        var sessionStartTxBytes: Long = 0L
            private set

        @Volatile
        private var activeInstance: LibboxVpnService? = null

        var statusCallback: ((String) -> Unit)? = null

        fun connectedElapsedSeconds(): Long {
            val startedAt = connectedAtElapsedMs
            if (!isRunning || startedAt <= 0L) return 0L
            return ((SystemClock.elapsedRealtime() - startedAt) / 1000L).coerceAtLeast(0L)
        }

        fun resetActiveNetwork(): Boolean {
            val instance = activeInstance ?: return false
            if (!isRunning) return false
            instance.scheduleNetworkReset(immediate = true)
            return true
        }

        fun saveQuickTileConfig(
            context: Context,
            configJson: String,
            killSwitch: Boolean,
            serverLabel: String?,
        ) {
            if (configJson.isBlank()) return
            try {
                val storage = AndroidKeystoreSecureStorage(context.applicationContext)
                storage.write(KEY_TILE_CONFIG, configJson, TILE_PREFS_NAME)
                storage.write(KEY_TILE_KILL_SWITCH, killSwitch.toString(), TILE_PREFS_NAME)
                if (!serverLabel.isNullOrBlank()) {
                    storage.write(KEY_TILE_LABEL, serverLabel.trim(), TILE_PREFS_NAME)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not persist Quick Tile config: ${e.javaClass.simpleName}")
            }
        }

        fun readQuickTileConfig(context: Context): QuickTileConfig? {
            return try {
                val storage = AndroidKeystoreSecureStorage(context.applicationContext)
                val cfg = storage.read(KEY_TILE_CONFIG, TILE_PREFS_NAME, resetOnError = false)
                if (cfg.isNullOrBlank()) return null
                val killSwitch =
                    storage.read(KEY_TILE_KILL_SWITCH, TILE_PREFS_NAME, resetOnError = false)
                        ?.toBoolean() ?: false
                val label = storage.read(KEY_TILE_LABEL, TILE_PREFS_NAME, resetOnError = false)
                QuickTileConfig(
                    configJson = cfg,
                    killSwitch = killSwitch,
                    serverLabel = label,
                )
            } catch (_: Exception) {
                null
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val stateLock = Any()
    private val worker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "Speedll-LibboxWorker").apply { isDaemon = true }
    }

    private lateinit var platformInterface: LibboxPlatformInterface
    private val stickyStorage by lazy { AndroidKeystoreSecureStorage(applicationContext) }

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

    @Volatile
    private var wakeLock: PowerManager.WakeLock? = null

    @Volatile
    private var wifiLock: WifiManager.WifiLock? = null

    @Volatile
    private var pendingWakeNetworkReset = false

    private var powerReceiverRegistered = false

    private val networkResetRunnable = Runnable {
        execute {
            performNetworkResetOnWorker()
        }
    }

    private val powerStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!isRunning || stopping) return
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> {
                    val shouldReset = pendingWakeNetworkReset
                    pendingWakeNetworkReset = false
                    execute {
                        val server = commandServer ?: return@execute
                        acquireTransitionWakeLock(2500L)
                        try {
                            syncWifiLock()
                            server.recordScreenState(true)
                            server.wake()
                            if (shouldReset) {
                                performNetworkResetOnWorker()
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Error handling SCREEN_ON: ${e.javaClass.simpleName}")
                        } finally {
                            releaseTransitionWakeLock()
                        }
                    }
                }

                Intent.ACTION_SCREEN_OFF -> {
                    // Record screen state without calling pause(), so background traffic,
                    // downloads, and messaging keep working while the screen is locked.
                    execute {
                        try {
                            commandServer?.recordScreenState(false)
                        } catch (e: Exception) {
                            Log.w(TAG, "Error handling SCREEN_OFF: ${e.javaClass.simpleName}")
                        }
                    }
                }

                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isDeviceIdle = pm?.isDeviceIdleMode == true
                    if (isDeviceIdle) {
                        pendingWakeNetworkReset = true
                        execute {
                            releaseWifiLock()
                            releaseTransitionWakeLock()
                            try {
                                commandServer?.pause()
                            } catch (e: Exception) {
                                Log.w(TAG, "Error handling Doze pause: ${e.javaClass.simpleName}")
                            }
                        }
                    } else {
                        pendingWakeNetworkReset = false
                        execute {
                            val server = commandServer ?: return@execute
                            acquireTransitionWakeLock(3000L)
                            try {
                                syncWifiLock()
                                server.wakeNow()
                                performNetworkResetOnWorker()
                            } catch (e: Exception) {
                                Log.w(TAG, "Error handling Doze wake: ${e.javaClass.simpleName}")
                            } finally {
                                releaseTransitionWakeLock()
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        platformInterface = LibboxPlatformInterface(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            val savedConfig = readStickyConfig()
            if (!savedConfig.isNullOrBlank() && VpnService.prepare(this) == null) {
                isKillSwitchEnabled = readStickyKillSwitch()
                try {
                    startForegroundCompat("در حال بازیابی تونل...")
                    execute {
                        startTunnelInternal(savedConfig)
                    }
                    return START_STICKY
                } catch (e: Exception) {
                    Log.w(TAG, "Sticky restart not permitted: ${e.javaClass.simpleName}")
                }
            }
            clearStickyConfig()
            stopSelf()
            return START_NOT_STICKY
        }

        when (intent.action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (config.isNullOrBlank()) {
                    clearStickyConfig()
                    updateStatus("failed:ERR-CORE-CONFIG")
                    stopSelf()
                    return START_NOT_STICKY
                }
                val killSwitch = intent.getBooleanExtra(EXTRA_KILL_SWITCH, false)
                val serverLabel = intent.getStringExtra(EXTRA_SERVER_LABEL)?.trim()
                if (!serverLabel.isNullOrBlank()) {
                    activeServerLabel = serverLabel
                }
                isKillSwitchEnabled = killSwitch
                saveStickyConfig(config, killSwitch)
                saveQuickTileConfig(this, config, killSwitch, activeServerLabel)
                startForegroundCompat("در حال آماده‌سازی تونل...")
                execute {
                    startTunnelInternal(config)
                }
                return START_STICKY
            }

            ACTION_STOP -> {
                clearStickyConfig()
                stopTunnelAndSelf()
                return START_NOT_STICKY
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
        val network = DefaultNetworkMonitor.defaultNetwork
        try {
            if (network != null) {
                setUnderlyingNetworks(arrayOf(network))
            } else {
                setUnderlyingNetworks(null)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not set underlying network: ${e.javaClass.simpleName}")
        }
    }

    internal fun onPhysicalNetworkUpdated(
        network: Network?,
        resetRequired: Boolean,
    ) {
        if (tunInterface == null) return
        try {
            if (network != null) {
                setUnderlyingNetworks(arrayOf(network))
            } else {
                setUnderlyingNetworks(null)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not update underlying network: ${e.javaClass.simpleName}")
        }

        syncWifiLock()
        if (resetRequired && isRunning && !stopping) {
            acquireTransitionWakeLock(2500L)
            scheduleNetworkReset(immediate = false)
        }
    }

    internal fun notifyDnsCacheCleared() {
        updateStatus(EVENT_DNS_CLEARED)
    }

    private fun scheduleNetworkReset(immediate: Boolean) {
        mainHandler.removeCallbacks(networkResetRunnable)
        if (immediate) {
            mainHandler.post(networkResetRunnable)
        } else {
            mainHandler.postDelayed(networkResetRunnable, NETWORK_RESET_DEBOUNCE_MS)
        }
    }

    private fun performNetworkResetOnWorker() {
        if (!isRunning || stopping || tunInterface == null) {
            releaseTransitionWakeLock()
            return
        }
        val server = commandServer ?: run {
            releaseTransitionWakeLock()
            return
        }
        acquireTransitionWakeLock(2000L)
        try {
            platformInterface.clearDNSCache()
            server.resetNetwork()
            Log.i(TAG, "Reset libbox network sockets and DNS cache after network change")
        } catch (e: Exception) {
            Log.w(TAG, "Could not reset libbox network: ${e.javaClass.simpleName}")
        } finally {
            releaseTransitionWakeLock()
        }
    }

    private fun startTunnelInternal(configJson: String) {
        val wasRunning = isRunning
        synchronized(stateLock) {
            stopping = false
            cleanupResourcesLocked()
            activeConfigJson = configJson
        }
        acquireTransitionWakeLock(5000L)

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
            if (!wasRunning) {
                tunnelSessionId += 1L
                connectedAtElapsedMs = SystemClock.elapsedRealtime()
                val uid = Process.myUid()
                val rx = TrafficStats.getUidRxBytes(uid)
                val tx = TrafficStats.getUidTxBytes(uid)
                sessionStartRxBytes =
                    if (rx == TrafficStats.UNSUPPORTED.toLong() || rx < 0L) 0L else rx
                sessionStartTxBytes =
                    if (tx == TrafficStats.UNSUPPORTED.toLong() || tx < 0L) 0L else tx
            } else if (connectedAtElapsedMs <= 0L) {
                connectedAtElapsedMs = SystemClock.elapsedRealtime()
            }
            syncWifiLock()
            registerPowerReceiver()

            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            try {
                server.recordScreenState(pm?.isInteractive != false)
            } catch (_: Exception) {
            }

            updateStatus("connected")
            updateNotification("اتصال برقرار است")
        } catch (e: Exception) {
            Log.e(TAG, "libbox start failed: ${e.message}", e)
            if (stopping) {
                cleanupResources()
            } else {
                fail("ERR-CORE-START")
            }
        } finally {
            releaseTransitionWakeLock()
        }
    }

    private fun fail(code: String) {
        clearStickyConfig()
        synchronized(stateLock) {
            stopping = true
            cleanupResourcesLocked()
        }
        isRunning = false
        activeServerLabel = null
        connectedAtElapsedMs = 0L
        sessionStartRxBytes = 0L
        sessionStartTxBytes = 0L
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
        activeServerLabel = null
        connectedAtElapsedMs = 0L
        sessionStartRxBytes = 0L
        sessionStartTxBytes = 0L
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
        mainHandler.removeCallbacks(networkResetRunnable)
        pendingWakeNetworkReset = false
        unregisterPowerReceiver()
        releaseKeepAliveLocks()

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

    /**
     * Acquires a bounded partial wake lock solely for brief startup/network-recovery
     * handoffs so the CPU can deep-sleep normally when the screen is off.
     */
    private fun acquireTransitionWakeLock(durationMs: Long = TRANSITION_WAKE_LOCK_MS) {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            if (wakeLock == null) {
                wakeLock = pm.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "$packageName:VpnTransitionWakeLock",
                ).apply {
                    setReferenceCounted(false)
                }
            }
            wakeLock?.acquire(durationMs)
        } catch (e: Exception) {
            Log.w(TAG, "Could not acquire transition WakeLock: ${e.javaClass.simpleName}")
        }
    }

    private fun releaseTransitionWakeLock() {
        try {
            val wl = wakeLock
            if (wl != null && wl.isHeld) {
                wl.release()
            }
        } catch (_: Exception) {
        }
    }

    /**
     * Holds a power-efficient Wi-Fi lock only while actively connected on Wi-Fi
     * outside Doze idle mode, releasing it on cellular networks or Doze sleep.
     */
    private fun syncWifiLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val isDeviceIdle = pm?.isDeviceIdleMode == true
        val shouldHoldWifiLock =
            isRunning && !stopping && DefaultNetworkMonitor.isWifiActive && !isDeviceIdle
        if (!shouldHoldWifiLock) {
            releaseWifiLock()
            return
        }

        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return
            if (wifiLock == null) {
                val lockMode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wifiLock = wm.createWifiLock(
                    lockMode,
                    "$packageName:VpnWifiLock",
                ).apply {
                    setReferenceCounted(false)
                }
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not acquire WifiLock: ${e.javaClass.simpleName}")
        }
    }

    private fun releaseWifiLock() {
        try {
            val wfl = wifiLock
            if (wfl != null && wfl.isHeld) {
                wfl.release()
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseKeepAliveLocks() {
        releaseTransitionWakeLock()
        wakeLock = null
        releaseWifiLock()
        wifiLock = null
    }

    private fun registerPowerReceiver() {
        if (powerReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(powerStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(powerStateReceiver, filter)
            }
            powerReceiverRegistered = true
        } catch (e: Exception) {
            Log.w(TAG, "Could not register power receiver: ${e.javaClass.simpleName}")
        }
    }

    private fun unregisterPowerReceiver() {
        if (!powerReceiverRegistered) return
        try {
            unregisterReceiver(powerStateReceiver)
        } catch (_: Exception) {
        }
        powerReceiverRegistered = false
    }

    private fun saveStickyConfig(configJson: String, killSwitch: Boolean) {
        try {
            stickyStorage.write(KEY_STICKY_CONFIG, configJson, STICKY_PREFS_NAME)
            stickyStorage.write(KEY_STICKY_KILL_SWITCH, killSwitch.toString(), STICKY_PREFS_NAME)
        } catch (e: Exception) {
            Log.w(TAG, "Could not persist sticky tunnel state: ${e.javaClass.simpleName}")
        }
    }

    private fun readStickyConfig(): String? {
        return try {
            stickyStorage.read(KEY_STICKY_CONFIG, STICKY_PREFS_NAME)
        } catch (_: Exception) {
            null
        }
    }

    private fun readStickyKillSwitch(): Boolean {
        return try {
            stickyStorage.read(KEY_STICKY_KILL_SWITCH, STICKY_PREFS_NAME)?.toBoolean() ?: false
        } catch (_: Exception) {
            false
        }
    }

    private fun clearStickyConfig() {
        try {
            stickyStorage.deleteAll(STICKY_PREFS_NAME)
        } catch (_: Exception) {
        }
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
        clearStickyConfig()
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
                isRunning = tunInterface != null
                if (isRunning) {
                    updateStatus("connected")
                    updateNotification("اتصال برقرار است")
                }
            } catch (e: Exception) {
                Log.e(TAG, "libbox reload failed: ${e.message}", e)
                fail("ERR-CORE-START")
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
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
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
            if (phase != EVENT_DNS_CLEARED) {
                SpeedllTileService.requestTileUpdate(this)
            }
        }
    }

    private fun execute(block: () -> Unit) {
        try {
            worker.execute(block)
        } catch (_: RejectedExecutionException) {
        }
    }

    override fun onRevoke() {
        clearStickyConfig()
        stopTunnelInternal()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        if (activeInstance === this) {
            activeInstance = null
        }
        stopTunnelInternal(notifyDisconnected = !stopping)
        SpeedllTileService.requestTileUpdate(this)
        worker.shutdownNow()
        super.onDestroy()
    }
}
