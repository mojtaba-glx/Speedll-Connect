package app.speedll.connect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

class SpeedllVpnService : VpnService() {

    companion object {
        const val TAG = "SpeedllVpnService"
        const val CHANNEL_ID = "speedll_vpn_channel"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "app.speedll.connect.START"
        const val ACTION_STOP = "app.speedll.connect.STOP"
        const val EXTRA_CONFIG = "extra_config"
        const val EXTRA_KILL_SWITCH = "extra_kill_switch"

        private const val LOCAL_SOCKS_HOST = "127.0.0.1"
        private const val LOCAL_SOCKS_PORT = 2080
        private const val LOCAL_DNS_PORT = 2053

        @Volatile
        var isRunning: Boolean = false
            private set

        var statusCallback: ((String) -> Unit)? = null
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val stopping = AtomicBoolean(false)
    private val reconnecting = AtomicBoolean(false)

    private var vpnInterface: ParcelFileDescriptor? = null
    private var coreProcess: Process? = null
    private var tunBridge: Tun2SocksBridge? = null
    private var activeConfigJson: String? = null
    private var lastCoreErrorLine: String? = null
    private var killSwitchEnabled: Boolean = false

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var activePhysicalNetwork: Network? = null

    override fun onCreate() {
        super.onCreate()
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY

        when (action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                killSwitchEnabled = intent.getBooleanExtra(EXTRA_KILL_SWITCH, false)
                if (!config.isNullOrEmpty()) {
                    startTunnelAsync(config)
                } else {
                    updateStatus("failed:ERR-CORE-CONFIG")
                }
            }
            ACTION_STOP -> {
                stopTunnel()
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Speedll Connect VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "نمایش وضعیت سرویس فعال Speedll Connect"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(statusText: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, SpeedllVpnService::class.java).apply {
            this.action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
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
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "قطع اتصال", stopPendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(statusText: String) {
        mainHandler.post {
            if (!stopping.get()) {
                val notificationManager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                notificationManager?.notify(NOTIFICATION_ID, buildNotification(statusText))
            }
        }
    }

    private fun startTunnelAsync(configJson: String) {
        stopping.set(false)
        activeConfigJson = configJson
        updateStatus("preparing")
        startForeground(NOTIFICATION_ID, buildNotification("در حال آماده‌سازی تونل..."))

        Thread({
            startTunnelInternal(configJson)
        }, "Speedll-TunnelStarter").start()
    }

    private fun startTunnelInternal(configJson: String) {
        try {
            // Stop any previous core/bridge/interface cleanly before starting or hot-switching
            val wasRunning = isRunning || coreProcess != null || vpnInterface != null
            stopCoreAndBridgeOnly()
            closeVpnInterface()
            if (wasRunning && !waitForPortFree(LOCAL_SOCKS_HOST, LOCAL_SOCKS_PORT, 2500)) {
                Log.w(TAG, "Local SOCKS port still busy before start")
            }

            val configFile = File(cacheDir, "current_config.json")
            FileOutputStream(configFile).use { out ->
                out.write(configJson.toByteArray(Charsets.UTF_8))
            }

            updateStatus("connecting")
            updateNotification("در حال راه‌اندازی هسته sing-box...")

            // Establish Android VPN interface and exclude our own package so sing-box outbound
            // sockets bypass tun0 and never loop back into the tunnel.
            val builder = Builder()
                .setSession("Speedll Connect")
                .setMtu(1500)
                .addAddress("172.19.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")

            if (killSwitchEnabled) {
                try {
                    builder.setBlocking(true)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not setBlocking: ${e.message}")
                }
                try {
                    builder.addAddress("fd00::1", 64)
                    builder.addRoute("::", 0)
                } catch (e: Exception) {
                    Log.w(TAG, "IPv6 route unavailable, IPv4-only tunnel: ${e.message}")
                }
            }

            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.w(TAG, "Could not add disallowed application: ${e.message}")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            val establishedInterface = builder.establish()
            if (establishedInterface == null) {
                Log.e(TAG, "Failed to establish VpnService interface")
                updateStatus("failed:ERR-TUN-ESTABLISH")
                stopSelf()
                return
            }
            vpnInterface = establishedInterface

            // Launch sing-box and verify it binds 127.0.0.1:2080 before declaring connected
            val coreStarted = launchAndVerifySingboxCore(configFile)
            if (!coreStarted) {
                val diagCode = classifyCoreFailure(lastCoreErrorLine)
                Log.e(TAG, "sing-box failed to start or bind port ($diagCode)")
                stopCoreAndBridgeOnly()
                isRunning = false
                if (keepKillSwitchBlocking(diagCode)) {
                    return
                }
                closeVpnInterface()
                updateStatus("failed:$diagCode")
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return
            }

            // Start user-space TUN-to-SOCKS5 + DNS bridge
            val bridge = Tun2SocksBridge(
                vpnInterface = establishedInterface,
                socksHost = LOCAL_SOCKS_HOST,
                socksPort = LOCAL_SOCKS_PORT,
                dnsPort = LOCAL_DNS_PORT
            )
            tunBridge = bridge
            bridge.start()

            isRunning = true
            registerNetworkSwitchMonitor()
            updateStatus("connected")
            updateNotification("اتصال برقرار است")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting tunnel: ${redactSensitive(e.message ?: "unknown")}")
            stopCoreAndBridgeOnly()
            isRunning = false
            if (keepKillSwitchBlocking("ERR-CORE-START")) {
                return
            }
            closeVpnInterface()
            updateStatus("failed:ERR-CORE-START")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun keepKillSwitchBlocking(diagnosticCode: String): Boolean {
        if (!killSwitchEnabled || vpnInterface == null) return false
        updateStatus("failed:$diagnosticCode")
        updateNotification("Kill Switch فعال است؛ ترافیک مسدود شد")
        return true
    }

    private fun waitForPortFree(host: String, port: Int, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (!isLocalPortListening(host, port)) return true
            Thread.sleep(50)
        }
        return !isLocalPortListening(host, port)
    }

    private fun launchAndVerifySingboxCore(configFile: File): Boolean {
        val nativeLibDir = applicationInfo.nativeLibraryDir
        val coreExecutable = File(nativeLibDir, "libsingbox.so")
        if (!coreExecutable.exists() || !coreExecutable.canExecute()) {
            Log.e(TAG, "Core executable missing or not executable")
            lastCoreErrorLine = "binary_missing"
            return false
        }

        lastCoreErrorLine = null
        val processBuilder = ProcessBuilder(
            coreExecutable.absolutePath,
            "run",
            "-c",
            configFile.absolutePath
        ).apply {
            directory(cacheDir)
            redirectErrorStream(true)
            environment()["SSL_CERT_DIR"] =
                "/system/etc/security/cacerts:/apex/com.android.conscrypt/cacerts"
        }

        val process = processBuilder.start()
        coreProcess = process

        Thread({
            try {
                process.inputStream.bufferedReader().forEachLine { line ->
                    val safeLine = redactSensitive(line)
                    Log.d("SingBoxCore", safeLine)
                    if (line.contains("FATAL", ignoreCase = true) ||
                        line.contains("ERROR", ignoreCase = true) ||
                        line.contains("decode config", ignoreCase = true)
                    ) {
                        lastCoreErrorLine = safeLine
                    }
                }
            } catch (_: Exception) {
            }
        }, "Speedll-SingBoxLog").apply {
            isDaemon = true
            start()
        }

        // Wait up to 6.0 seconds for sing-box to open 127.0.0.1:2080 while remaining alive
        val deadline = System.currentTimeMillis() + 6000L
        while (System.currentTimeMillis() < deadline) {
            if (!isProcessAlive(process)) {
                return false
            }
            if (isLocalPortListening(LOCAL_SOCKS_HOST, LOCAL_SOCKS_PORT)) {
                startCoreCrashWatcher(process)
                return true
            }
            Thread.sleep(100)
        }

        return false
    }

    private fun startCoreCrashWatcher(process: Process) {
        Thread({
            try {
                val exitCode = process.waitFor()
                if (isRunning && !stopping.get() && !reconnecting.get() && coreProcess === process) {
                    Log.w(TAG, "sing-box exited unexpectedly with code $exitCode")
                    recoverCoreAfterNetworkSwitch()
                }
            } catch (_: InterruptedException) {
            }
        }, "Speedll-CoreWatcher").apply {
            isDaemon = true
            start()
        }
    }

    private fun registerNetworkSwitchMonitor() {
        unregisterNetworkSwitchMonitor()
        val cm = connectivityManager ?: return

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val previous = activePhysicalNetwork
                activePhysicalNetwork = network
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    try {
                        setUnderlyingNetworks(arrayOf(network))
                    } catch (_: Exception) {
                    }
                }
                if (previous != null && previous != network && isRunning && !stopping.get()) {
                    Log.i(TAG, "Physical network switched; triggering controlled recovery")
                    recoverCoreAfterNetworkSwitch()
                }
            }

            override fun onLost(network: Network) {
                if (activePhysicalNetwork == network && isRunning && !stopping.get()) {
                    Log.i(TAG, "Active physical network lost; waiting for fallback network")
                    updateStatus("reconnecting")
                    updateNotification("در انتظار اتصال شبکه جدید...")
                }
            }
        }

        try {
            cm.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (e: Exception) {
            Log.w(TAG, "Could not register NetworkCallback: ${e.message}")
        }
    }

    private fun unregisterNetworkSwitchMonitor() {
        val cm = connectivityManager
        val cb = networkCallback
        networkCallback = null
        activePhysicalNetwork = null
        if (cm != null && cb != null) {
            try {
                cm.unregisterNetworkCallback(cb)
            } catch (_: Exception) {
            }
        }
    }

    private fun recoverCoreAfterNetworkSwitch() {
        if (!isRunning || stopping.get()) return
        if (!reconnecting.compareAndSet(false, true)) return

        Thread({
            try {
                updateStatus("reconnecting")
                updateNotification("در حال بازیابی اتصال پس از تغییر شبکه...")

                val configJson = activeConfigJson
                if (configJson.isNullOrEmpty()) {
                    updateStatus("failed:ERR-CORE-CONFIG")
                    return@Thread
                }

                val configFile = File(cacheDir, "current_config.json")
                FileOutputStream(configFile).use { out ->
                    out.write(configJson.toByteArray(Charsets.UTF_8))
                }

                try {
                    coreProcess?.destroy()
                    coreProcess = null
                } catch (_: Exception) {
                }

                waitForPortFree(LOCAL_SOCKS_HOST, LOCAL_SOCKS_PORT, 2500)

                val restarted = launchAndVerifySingboxCore(configFile)
                if (restarted && !stopping.get()) {
                    updateStatus("connected")
                    updateNotification("اتصال برقرار است")
                } else if (!stopping.get()) {
                    if (!keepKillSwitchBlocking("ERR-NET-SWITCH")) {
                        updateStatus("failed:ERR-NET-SWITCH")
                        stopTunnel()
                        stopSelf()
                    }
                }
            } catch (_: Exception) {
                if (!stopping.get()) {
                    if (!keepKillSwitchBlocking("ERR-NET-SWITCH")) {
                        updateStatus("failed:ERR-NET-SWITCH")
                        stopTunnel()
                        stopSelf()
                    }
                }
            } finally {
                reconnecting.set(false)
            }
        }, "Speedll-ReconnectWorker").start()
    }

    private fun isProcessAlive(process: Process): Boolean {
        return try {
            process.exitValue()
            false
        } catch (_: IllegalThreadStateException) {
            true
        }
    }

    private fun isLocalPortListening(host: String, port: Int): Boolean {
        var socket: Socket? = null
        return try {
            socket = Socket()
            socket.connect(InetSocketAddress(host, port), 150)
            true
        } catch (_: Exception) {
            false
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun classifyCoreFailure(errorLine: String?): String {
        val lower = (errorLine ?: "").lowercase()
        return when {
            lower.contains("binary_missing") -> "ERR-CORE-BINARY"
            lower.contains("decode config") || lower.contains("unknown field") -> "ERR-CORE-CONFIG"
            lower.contains("address already in use") -> "ERR-CORE-PORT"
            lower.contains("permission denied") -> "ERR-CORE-PERM"
            else -> "ERR-CORE-START"
        }
    }

    private fun redactSensitive(input: String): String {
        return input
            .replace(
                Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"),
                "[REDACTED-UUID]"
            )
            .replace(Regex("(\\d{1,3}\\.){3}\\d{1,3}"), "[REDACTED-IP]")
    }

    private fun stopCoreAndBridgeOnly() {
        try {
            tunBridge?.stop()
            tunBridge = null
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping Tun2SocksBridge: ${e.message}")
        }

        try {
            coreProcess?.destroy()
            coreProcess = null
        } catch (e: Exception) {
            Log.w(TAG, "Error destroying core process: ${e.message}")
        }
    }

    private fun closeVpnInterface() {
        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            Log.w(TAG, "Error closing VPN interface: ${e.message}")
        }
    }

    private fun stopTunnel() {
        stopping.set(true)
        isRunning = false
        unregisterNetworkSwitchMonitor()
        stopCoreAndBridgeOnly()
        closeVpnInterface()
        updateStatus("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun updateStatus(phase: String) {
        mainHandler.post {
            statusCallback?.invoke(phase)
        }
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopTunnel()
        super.onRevoke()
    }
}
