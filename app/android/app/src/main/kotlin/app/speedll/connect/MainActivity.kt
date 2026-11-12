package app.speedll.connect

import android.Manifest
import android.app.Activity
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.TrafficStats
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "app.speedll.connect/vpn"
        private const val EVENT_CHANNEL = "app.speedll.connect/vpn_events"
        private const val SECURE_STORAGE_CHANNEL = "plugins.it_nomads.com/flutter_secure_storage"
        private const val QR_SCANNER_CHANNEL = "app.speedll.connect/qr_scanner"
        private const val SHARE_CHANNEL = "app.speedll.connect/share"
        private const val STATS_POLL_INTERVAL_MS = 1500L
        private const val VPN_REQUEST_CODE = 2001
        private const val QR_SCAN_REQUEST_CODE = 2002
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 2003
        const val EXTRA_QUICK_TILE_CONNECT = "extra_quick_tile_connect"
        private const val EVENT_QUICK_TILE_CONNECT = "event:quick_tile_connect"
    }

    private val statsHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var activeStatusCallback: ((String) -> Unit)? = null
    private var pendingConfigJson: String? = null
    private var pendingKillSwitch: Boolean = false
    private var pendingServerLabel: String? = null
    private var pendingQuickTileConnect: Boolean = false
    private var pendingResult: MethodChannel.Result? = null
    private var pendingQrResult: MethodChannel.Result? = null
    private lateinit var secureStorage: AndroidKeystoreSecureStorage

    private var isUiResumed: Boolean = false
    private var statsSamplerRunning: Boolean = false
    private var observedSessionId: Long = -1L
    private var sessionStartRx: Long = 0L
    private var sessionStartTx: Long = 0L
    private var lastSampleRx: Long = 0L
    private var lastSampleTx: Long = 0L
    private var lastSampleElapsedMs: Long = 0L

    private val trafficStatsRunnable = object : Runnable {
        override fun run() {
            if (!isUiResumed || eventSink == null) {
                statsSamplerRunning = false
                return
            }
            emitTrafficSample()
            statsHandler.postDelayed(this, STATS_POLL_INTERVAL_MS)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        secureStorage = AndroidKeystoreSecureStorage(applicationContext)

        // Status event stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    val callback: (String) -> Unit = { phase ->
                        runOnUiThread {
                            eventSink?.success(phase)
                            if (phase == "connected") {
                                resetTrafficBaseline(LibboxVpnService.tunnelSessionId)
                                syncTrafficSampler()
                            } else if (phase == "disconnected" || phase.startsWith("failed")) {
                                observedSessionId = -1L
                            }
                        }
                    }
                    activeStatusCallback = callback
                    LibboxVpnService.statusCallback = callback
                    if (LibboxVpnService.isRunning) {
                        events?.success("connected")
                        resetTrafficBaseline(LibboxVpnService.tunnelSessionId)
                    }
                    if (pendingQuickTileConnect) {
                        pendingQuickTileConnect = false
                        events?.success(EVENT_QUICK_TILE_CONNECT)
                    }
                    syncTrafficSampler()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    if (LibboxVpnService.statusCallback === activeStatusCallback) {
                        LibboxVpnService.statusCallback = null
                    }
                    activeStatusCallback = null
                    stopTrafficSampler()
                }
            })

        // Android Keystore Secure Storage channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    val options = call.argument<Map<String, Any>>("options")
                    val prefsName = options?.get("sharedPreferencesName") as? String
                    val resetOnError = (options?.get("resetOnError") as? String)?.toBoolean() ?: true

                    when (call.method) {
                        "write" -> {
                            if (key == null) {
                                result.error("INVALID_KEY", "Key cannot be null", null)
                            } else if (value == null) {
                                secureStorage.delete(key, prefsName)
                                result.success(null)
                            } else {
                                secureStorage.write(key, value, prefsName)
                                result.success(null)
                            }
                        }
                        "read" -> {
                            if (key == null) {
                                result.error("INVALID_KEY", "Key cannot be null", null)
                            } else {
                                result.success(secureStorage.read(key, prefsName, resetOnError))
                            }
                        }
                        "containsKey" -> {
                            if (key == null) {
                                result.success(false)
                            } else {
                                result.success(secureStorage.containsKey(key, prefsName))
                            }
                        }
                        "delete" -> {
                            if (key != null) {
                                secureStorage.delete(key, prefsName)
                            }
                            result.success(null)
                        }
                        "readAll" -> {
                            result.success(secureStorage.readAll(prefsName, resetOnError))
                        }
                        "deleteAll" -> {
                            secureStorage.deleteAll(prefsName)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("KEYSTORE_ERROR", e.message, null)
                }
            }

        // Camera QR Code Scanner channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QR_SCANNER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scanQrCode" -> {
                        if (pendingQrResult != null) {
                            result.error("ALREADY_ACTIVE", "اسکنر دوربین در حال اجراست", null)
                            return@setMethodCallHandler
                        }
                        pendingQrResult = result
                        val intent = Intent(this, QrScannerActivity::class.java)
                        startActivityForResult(intent, QR_SCAN_REQUEST_CODE)
                    }
                    else -> result.notImplemented()
                }
            }

        // Offline QR matrix generation (ZXing) + System Share Sheet channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "generateQrMatrix" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrEmpty()) {
                            result.error("INVALID_QR_TEXT", "QR content is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val hints = mapOf(
                                EncodeHintType.CHARACTER_SET to "UTF-8",
                                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
                                EncodeHintType.MARGIN to 1,
                            )
                            val matrix = QRCodeWriter().encode(
                                text,
                                BarcodeFormat.QR_CODE,
                                0,
                                0,
                                hints,
                            )
                            val size = matrix.width
                            val height = matrix.height
                            val modules = ByteArray(size * height)
                            for (y in 0 until height) {
                                val rowOffset = y * size
                                for (x in 0 until size) {
                                    modules[rowOffset + x] = if (matrix.get(x, y)) 1 else 0
                                }
                            }
                            result.success(
                                mapOf(
                                    "size" to size,
                                    "modules" to modules,
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("QR_ENCODE_FAILED", e.message, null)
                        }
                    }
                    "shareText" -> {
                        val text = call.argument<String>("text")
                        val subject = call.argument<String>("subject")
                        if (text.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                                if (!subject.isNullOrBlank()) {
                                    putExtra(Intent.EXTRA_SUBJECT, subject)
                                }
                            }
                            val chooser = Intent.createChooser(sendIntent, subject ?: "Speedll Connect")
                            startActivity(chooser)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // VPN Method invocation channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    }
                    "requestPermissionAndStart" -> {
                        val configJson = call.argument<String>("config")
                        val killSwitch = call.argument<Boolean>("killSwitch") ?: false
                        val serverLabel = call.argument<String>("serverLabel")?.trim()
                        if (configJson.isNullOrEmpty()) {
                            result.error("INVALID_CONFIG", "کانفیگ ارسالی خالی است", null)
                            return@setMethodCallHandler
                        }

                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            pendingConfigJson = configJson
                            pendingKillSwitch = killSwitch
                            pendingServerLabel = serverLabel
                            pendingResult = result
                            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                        } else {
                            requestNotificationPermissionIfNeeded()
                            startVpnService(configJson, killSwitch, serverLabel)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        stopVpnService()
                        result.success(true)
                    }
                    "isRunning" -> {
                        result.success(LibboxVpnService.isRunning)
                    }
                    "getNativeTunnelState" -> {
                        result.success(
                            mapOf(
                                "isRunning" to LibboxVpnService.isRunning,
                                "connectedSeconds" to LibboxVpnService.connectedElapsedSeconds(),
                            ),
                        )
                    }
                    "resetNetwork" -> {
                        result.success(LibboxVpnService.resetActiveNetwork())
                    }
                    "openVpnSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_VPN_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                            result.success(pm?.isIgnoringBatteryOptimizations(packageName) == true)
                        } else {
                            result.success(true)
                        }
                    }
                    "openBatteryOptimizationSettings" -> {
                        try {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "canRequestAddQuickSettingsTile" -> {
                        result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    }
                    "requestAddQuickSettingsTile" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val statusBarManager = getSystemService(StatusBarManager::class.java)
                            if (statusBarManager == null) {
                                result.success("unsupported")
                            } else {
                                statusBarManager.requestAddTileService(
                                    ComponentName(this, SpeedllTileService::class.java),
                                    "Speedll Connect",
                                    Icon.createWithResource(this, R.drawable.ic_qs_speedll),
                                    mainExecutor,
                                ) { status ->
                                    val code = when (status) {
                                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "added"
                                        StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED ->
                                            "already_added"
                                        else -> "denied"
                                    }
                                    runOnUiThread {
                                        result.success(code)
                                    }
                                }
                            }
                        } else {
                            result.success("unsupported")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST_CODE
            )
        }
    }

    private fun startVpnService(
        configJson: String,
        killSwitch: Boolean,
        serverLabel: String? = null,
    ) {
        val intent = Intent(this, LibboxVpnService::class.java).apply {
            action = LibboxVpnService.ACTION_START
            putExtra(LibboxVpnService.EXTRA_CONFIG, configJson)
            putExtra(LibboxVpnService.EXTRA_KILL_SWITCH, killSwitch)
            if (!serverLabel.isNullOrBlank()) {
                putExtra(LibboxVpnService.EXTRA_SERVER_LABEL, serverLabel)
            }
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopVpnService() {
        val intent = Intent(this, LibboxVpnService::class.java).apply {
            action = LibboxVpnService.ACTION_STOP
        }
        startService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val config = pendingConfigJson
                if (config != null) {
                    requestNotificationPermissionIfNeeded()
                    startVpnService(config, pendingKillSwitch, pendingServerLabel)
                    pendingResult?.success(true)
                } else {
                    pendingResult?.error("CONFIG_LOST", "کانفیگ یافت نشد", null)
                }
            } else {
                pendingResult?.error("PERMISSION_DENIED", "کاربر مجوز VPN را تأیید نکرد", null)
            }
            pendingConfigJson = null
            pendingKillSwitch = false
            pendingServerLabel = null
            pendingResult = null
        } else if (requestCode == QR_SCAN_REQUEST_CODE) {
            val qrResult = pendingQrResult
            pendingQrResult = null
            if (resultCode == Activity.RESULT_OK) {
                val scanned = data?.getStringExtra(QrScannerActivity.EXTRA_QR_RESULT)
                qrResult?.success(scanned)
            } else {
                val errorMsg = data?.getStringExtra(QrScannerActivity.EXTRA_ERROR_MESSAGE)
                if (!errorMsg.isNullOrEmpty()) {
                    qrResult?.error("SCAN_ERROR", errorMsg, null)
                } else {
                    qrResult?.error("CANCELLED", "اسکن بارکد لغو شد", null)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleQuickTileIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleQuickTileIntent(intent)
    }

    private fun handleQuickTileIntent(incoming: Intent?) {
        if (incoming?.getBooleanExtra(EXTRA_QUICK_TILE_CONNECT, false) != true) {
            return
        }
        incoming.removeExtra(EXTRA_QUICK_TILE_CONNECT)
        if (LibboxVpnService.isRunning) {
            return
        }
        val sink = eventSink
        if (sink != null) {
            runOnUiThread {
                eventSink?.success(EVENT_QUICK_TILE_CONNECT)
            }
        } else {
            pendingQuickTileConnect = true
        }
    }

    override fun onResume() {
        super.onResume()
        isUiResumed = true
        syncTrafficSampler()
    }

    override fun onPause() {
        isUiResumed = false
        stopTrafficSampler()
        super.onPause()
    }

    private fun syncTrafficSampler() {
        if (isUiResumed && eventSink != null) {
            if (!statsSamplerRunning) {
                statsSamplerRunning = true
                statsHandler.post(trafficStatsRunnable)
            }
        } else {
            stopTrafficSampler()
        }
    }

    private fun stopTrafficSampler() {
        statsHandler.removeCallbacks(trafficStatsRunnable)
        statsSamplerRunning = false
    }

    private fun currentUidBytes(): Pair<Long, Long> {
        val uid = Process.myUid()
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        return Pair(
            if (rx == TrafficStats.UNSUPPORTED.toLong() || rx < 0L) 0L else rx,
            if (tx == TrafficStats.UNSUPPORTED.toLong() || tx < 0L) 0L else tx,
        )
    }

    private fun resetTrafficBaseline(sessionId: Long) {
        val (rx, tx) = currentUidBytes()
        val nativeStartRx = LibboxVpnService.sessionStartRxBytes
        val nativeStartTx = LibboxVpnService.sessionStartTxBytes
        observedSessionId = sessionId
        sessionStartRx = if (nativeStartRx > 0L && rx >= nativeStartRx) nativeStartRx else rx
        sessionStartTx = if (nativeStartTx > 0L && tx >= nativeStartTx) nativeStartTx else tx
        lastSampleRx = rx
        lastSampleTx = tx
        lastSampleElapsedMs = SystemClock.elapsedRealtime()
    }

    private fun emitTrafficSample() {
        if (!LibboxVpnService.isRunning) {
            observedSessionId = -1L
            return
        }
        val sessionId = LibboxVpnService.tunnelSessionId
        val (rx, tx) = currentUidBytes()
        val nowMs = SystemClock.elapsedRealtime()

        if (observedSessionId != sessionId || lastSampleElapsedMs <= 0L) {
            resetTrafficBaseline(sessionId)
            val downlinkTotal = (rx - sessionStartRx).coerceAtLeast(0L)
            val uplinkTotal = (tx - sessionStartTx).coerceAtLeast(0L)
            eventSink?.success("stats:0:0:$uplinkTotal:$downlinkTotal")
            return
        }

        val elapsedMs = (nowMs - lastSampleElapsedMs).coerceAtLeast(1L)
        val deltaRx = (rx - lastSampleRx).coerceAtLeast(0L)
        val deltaTx = (tx - lastSampleTx).coerceAtLeast(0L)
        val downlinkBps = (deltaRx * 1000L) / elapsedMs
        val uplinkBps = (deltaTx * 1000L) / elapsedMs
        val downlinkTotal = (rx - sessionStartRx).coerceAtLeast(0L)
        val uplinkTotal = (tx - sessionStartTx).coerceAtLeast(0L)

        lastSampleRx = rx
        lastSampleTx = tx
        lastSampleElapsedMs = nowMs

        eventSink?.success("stats:$uplinkBps:$downlinkBps:$uplinkTotal:$downlinkTotal")
    }

    override fun onDestroy() {
        isUiResumed = false
        stopTrafficSampler()
        if (LibboxVpnService.statusCallback === activeStatusCallback) {
            LibboxVpnService.statusCallback = null
        }
        activeStatusCallback = null
        eventSink = null
        super.onDestroy()
    }
}
