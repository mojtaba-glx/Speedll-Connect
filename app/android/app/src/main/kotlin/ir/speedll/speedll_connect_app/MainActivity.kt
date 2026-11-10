package ir.speedll.speedll_connect_app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "ir.speedll.speedll_connect/vpn"
        private const val EVENT_CHANNEL = "ir.speedll.speedll_connect/vpn_events"
        private const val VPN_REQUEST_CODE = 2001
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingConfigJson: String? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Status event stream
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    SpeedllVpnService.statusCallback = { phase ->
                        runOnUiThread {
                            eventSink?.success(phase)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    SpeedllVpnService.statusCallback = null
                }
            })

        // Method invocation channel
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
                        if (configJson.isNullOrEmpty()) {
                            result.error("INVALID_CONFIG", "کانفیگ ارسالی خالی است", null)
                            return@setMethodCallHandler
                        }

                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            pendingConfigJson = configJson
                            pendingResult = result
                            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                        } else {
                            startVpnService(configJson)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        stopVpnService()
                        result.success(true)
                    }
                    "isRunning" -> {
                        result.success(SpeedllVpnService.isRunning)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startVpnService(configJson: String) {
        val intent = Intent(this, SpeedllVpnService::class.java).apply {
            action = SpeedllVpnService.ACTION_START
            putExtra(SpeedllVpnService.EXTRA_CONFIG, configJson)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopVpnService() {
        val intent = Intent(this, SpeedllVpnService::class.java).apply {
            action = SpeedllVpnService.ACTION_STOP
        }
        startService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val config = pendingConfigJson
                if (config != null) {
                    startVpnService(config)
                    pendingResult?.success(true)
                } else {
                    pendingResult?.error("CONFIG_LOST", "کانفیگ یافت نشد", null)
                }
            } else {
                pendingResult?.error("PERMISSION_DENIED", "کاربر مجوز VPN را تأیید نکرد", null)
            }
            pendingConfigJson = null
            pendingResult = null
        }
    }
}
