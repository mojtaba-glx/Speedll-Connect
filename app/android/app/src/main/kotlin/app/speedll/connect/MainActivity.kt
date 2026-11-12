package app.speedll.connect

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
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
        private const val VPN_REQUEST_CODE = 2001
        private const val QR_SCAN_REQUEST_CODE = 2002
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 2003

        @Volatile
        private var lastStartedNativeLibbox: Boolean? = null
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingConfigJson: String? = null
    private var pendingKillSwitch: Boolean = false
    private var pendingNativeLibbox: Boolean = true
    private var pendingResult: MethodChannel.Result? = null
    private var pendingQrResult: MethodChannel.Result? = null
    private lateinit var secureStorage: AndroidKeystoreSecureStorage

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
                        }
                    }
                    SpeedllVpnService.statusCallback = callback
                    LibboxVpnService.statusCallback = callback
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    SpeedllVpnService.statusCallback = null
                    LibboxVpnService.statusCallback = null
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
                        val nativeLibbox = call.argument<Boolean>("nativeLibbox") ?: true
                        if (configJson.isNullOrEmpty()) {
                            result.error("INVALID_CONFIG", "کانفیگ ارسالی خالی است", null)
                            return@setMethodCallHandler
                        }

                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            pendingConfigJson = configJson
                            pendingKillSwitch = killSwitch
                            pendingNativeLibbox = nativeLibbox
                            pendingResult = result
                            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                        } else {
                            requestNotificationPermissionIfNeeded()
                            startVpnService(configJson, killSwitch, nativeLibbox)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        stopVpnService()
                        result.success(true)
                    }
                    "isRunning" -> {
                        result.success(
                            LibboxVpnService.isRunning || SpeedllVpnService.isRunning
                        )
                    }
                    "openVpnSettings" -> {
                        try {
                            val intent = android.content.Intent(android.provider.Settings.ACTION_VPN_SETTINGS).apply {
                                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
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
        nativeLibbox: Boolean,
    ) {
        lastStartedNativeLibbox = nativeLibbox
        val intent = if (nativeLibbox) {
            Intent(this, LibboxVpnService::class.java).apply {
                action = LibboxVpnService.ACTION_START
                putExtra(LibboxVpnService.EXTRA_CONFIG, configJson)
                putExtra(LibboxVpnService.EXTRA_KILL_SWITCH, killSwitch)
            }
        } else {
            Intent(this, SpeedllVpnService::class.java).apply {
                action = SpeedllVpnService.ACTION_START
                putExtra(SpeedllVpnService.EXTRA_CONFIG, configJson)
                putExtra(SpeedllVpnService.EXTRA_KILL_SWITCH, killSwitch)
            }
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopVpnService() {
        when (lastStartedNativeLibbox) {
            true -> sendStopAction(LibboxVpnService::class.java, LibboxVpnService.ACTION_STOP)
            false -> sendStopAction(SpeedllVpnService::class.java, SpeedllVpnService.ACTION_STOP)
            null -> {
                sendStopAction(LibboxVpnService::class.java, LibboxVpnService.ACTION_STOP)
                sendStopAction(SpeedllVpnService::class.java, SpeedllVpnService.ACTION_STOP)
            }
        }
        lastStartedNativeLibbox = null
    }

    private fun sendStopAction(serviceClass: Class<*>, action: String) {
        val intent = Intent(this, serviceClass).apply {
            this.action = action
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
                    startVpnService(config, pendingKillSwitch, pendingNativeLibbox)
                    pendingResult?.success(true)
                } else {
                    pendingResult?.error("CONFIG_LOST", "کانفیگ یافت نشد", null)
                }
            } else {
                pendingResult?.error("PERMISSION_DENIED", "کاربر مجوز VPN را تأیید نکرد", null)
            }
            pendingConfigJson = null
            pendingKillSwitch = false
            pendingNativeLibbox = true
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
}
