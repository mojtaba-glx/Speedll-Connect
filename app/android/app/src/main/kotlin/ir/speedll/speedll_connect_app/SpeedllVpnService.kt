package ir.speedll.speedll_connect_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileOutputStream

class SpeedllVpnService : VpnService() {

    companion object {
        const val TAG = "SpeedllVpnService"
        const val CHANNEL_ID = "speedll_vpn_channel"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START = "ir.speedll.speedll_connect.START"
        const val ACTION_STOP = "ir.speedll.speedll_connect.STOP"
        const val EXTRA_CONFIG = "extra_config"

        var isRunning: Boolean = false
            private set

        var statusCallback: ((String) -> Unit)? = null
    }

    private var vpnInterface: ParcelFileDescriptor? = null
    private var coreProcess: Process? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY

        when (action) {
            ACTION_START -> {
                val config = intent.getStringExtra(EXTRA_CONFIG)
                if (!config.isNullOrEmpty()) {
                    startTunnel(config)
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

    private fun startTunnel(configJson: String) {
        try {
            updateStatus("preparing")
            startForeground(NOTIFICATION_ID, buildNotification("در حال اتصال..."))

            // Save config to private cache directory
            val configFile = File(cacheDir, "current_config.json")
            FileOutputStream(configFile).use { out ->
                out.write(configJson.toByteArray(Charsets.UTF_8))
            }

            // Establish standard Android VPN tunnel interface
            val builder = Builder()
                .setSession("Speedll Connect")
                .setMtu(1500)
                .addAddress("172.19.0.1", 30)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("1.1.1.1")
                .addDnsServer("8.8.8.8")

            vpnInterface = builder.establish()
            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VpnService interface")
                updateStatus("failed")
                stopSelf()
                return
            }

            val nativeLibDir = applicationInfo.nativeLibraryDir
            val coreExecutable = File(nativeLibDir, "libsingbox.so")

            if (coreExecutable.exists() && coreExecutable.canExecute()) {
                Log.i(TAG, "Starting sing-box core from: ${coreExecutable.absolutePath}")
                val processBuilder = ProcessBuilder(
                    coreExecutable.absolutePath,
                    "run",
                    "-c",
                    configFile.absolutePath
                )
                processBuilder.redirectErrorStream(true)
                coreProcess = processBuilder.start()

                Thread {
                    try {
                        coreProcess?.inputStream?.bufferedReader()?.forEachLine { line ->
                            Log.d("SingBoxCore", line)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Core output stream error: $e")
                    }
                }.start()
            } else {
                Log.w(TAG, "Core executable not found or not executable at: ${coreExecutable.absolutePath}")
            }

            isRunning = true
            updateStatus("connected")
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, buildNotification("اتصال برقرار است"))

        } catch (e: Exception) {
            Log.e(TAG, "Error starting tunnel: $e")
            updateStatus("failed")
            stopTunnel()
            stopSelf()
        }
    }

    private fun stopTunnel() {
        isRunning = false
        try {
            coreProcess?.destroy()
            coreProcess = null
        } catch (e: Exception) {
            Log.e(TAG, "Error destroying core process: $e")
        }

        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface: $e")
        }

        updateStatus("disconnected")
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun updateStatus(phase: String) {
        statusCallback?.invoke(phase)
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
