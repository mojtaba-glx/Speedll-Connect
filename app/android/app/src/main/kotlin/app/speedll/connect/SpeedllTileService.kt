package app.speedll.connect

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Android Quick Settings Tile (API 24+) allowing one-tap VPN connect/disconnect
 * directly from the system status bar shade.
 */
class SpeedllTileService : TileService() {

    companion object {
        private const val TAG = "SpeedllTileService"
        private const val TILE_ACTIVITY_REQUEST_CODE = 1003

        fun requestTileUpdate(context: Context) {
            try {
                requestListeningState(
                    context.applicationContext,
                    ComponentName(context.applicationContext, SpeedllTileService::class.java),
                )
            } catch (e: Exception) {
                Log.w(TAG, "Could not request Quick Settings tile refresh: ${e.javaClass.simpleName}")
            }
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        syncTileVisual()
    }

    override fun onStartListening() {
        super.onStartListening()
        syncTileVisual()
    }

    override fun onClick() {
        super.onClick()

        if (LibboxVpnService.isRunning) {
            updateTileVisual(
                active = false,
                subtitleText = "در حال قطع...",
            )
            try {
                val stopIntent = Intent(this, LibboxVpnService::class.java).apply {
                    action = LibboxVpnService.ACTION_STOP
                }
                startService(stopIntent)
            } catch (e: Exception) {
                Log.w(TAG, "Quick Tile stop failed: ${e.javaClass.simpleName}")
                openMainActivity(autoConnect = false)
            }
            return
        }

        val hasVpnPermission = VpnService.prepare(this) == null
        val savedTile = LibboxVpnService.readQuickTileConfig(this)
        if (hasVpnPermission && !savedTile?.configJson.isNullOrBlank()) {
            val startIntent = Intent(this, LibboxVpnService::class.java).apply {
                action = LibboxVpnService.ACTION_START
                putExtra(LibboxVpnService.EXTRA_CONFIG, savedTile!!.configJson)
                putExtra(LibboxVpnService.EXTRA_KILL_SWITCH, savedTile.killSwitch)
                if (!savedTile.serverLabel.isNullOrBlank()) {
                    putExtra(LibboxVpnService.EXTRA_SERVER_LABEL, savedTile.serverLabel)
                }
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(startIntent)
                } else {
                    startService(startIntent)
                }
                updateTileVisual(
                    active = true,
                    subtitleText = "در حال اتصال...",
                )
                return
            } catch (e: Exception) {
                // On strict Android 12-15/MIUI policies, background FGS from TileService
                // may be denied; fall back to opening MainActivity to start in foreground.
                Log.i(TAG, "Background FGS blocked from Quick Tile; launching UI: ${e.javaClass.simpleName}")
            }
        }

        val shouldAutoConnect = !savedTile?.configJson.isNullOrBlank()
        if (isLocked) {
            unlockAndRun {
                openMainActivity(autoConnect = shouldAutoConnect)
            }
        } else {
            openMainActivity(autoConnect = shouldAutoConnect)
        }
    }

    private fun syncTileVisual() {
        val running = LibboxVpnService.isRunning
        val label = LibboxVpnService.activeServerLabel
            ?: LibboxVpnService.readQuickTileConfig(this)?.serverLabel
        val subtitle = if (running) {
            if (!label.isNullOrBlank()) label else "متصل"
        } else {
            "قطع شده"
        }
        updateTileVisual(active = running, subtitleText = subtitle)
    }

    private fun updateTileVisual(
        active: Boolean,
        subtitleText: String,
    ) {
        val tile = qsTile ?: return
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Speedll Connect"
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_speedll)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = subtitleText
        }
        tile.contentDescription = "Speedll Connect - $subtitleText"
        try {
            tile.updateTile()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to update Quick Tile: ${e.javaClass.simpleName}")
        }
    }

    private fun openMainActivity(autoConnect: Boolean) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (autoConnect) {
                putExtra(MainActivity.EXTRA_QUICK_TILE_CONNECT, true)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                TILE_ACTIVITY_REQUEST_CODE,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        }
    }
}
