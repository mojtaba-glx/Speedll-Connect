package app.speedll.connect

import android.os.Build
import android.util.Log
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.LocalDNSTransport
import java.net.InetAddress

class LocalResolver : LocalDNSTransport {
    private companion object {
        const val TAG = "SpeedllLocalResolver"
    }

    override fun raw(): Boolean = false

    override fun lookup(ctx: ExchangeContext?, network: String?, domain: String?) {
        if (ctx == null) return
        if (domain.isNullOrBlank()) {
            ctx.errorCode(1)
            return
        }

        try {
            val net = DefaultNetworkMonitor.defaultNetwork
            val addresses = if (net != null) {
                net.getAllByName(domain)
            } else {
                InetAddress.getAllByName(domain)
            }

            if (addresses.isNullOrEmpty()) {
                ctx.errorCode(1)
            } else {
                val ips = addresses.joinToString("\n") { it.hostAddress ?: "" }.trim()
                if (ips.isEmpty()) {
                    ctx.errorCode(1)
                } else {
                    ctx.success(ips)
                }
            }
        } catch (_: Exception) {
            ctx.errorCode(1)
        }
    }

    override fun exchange(ctx: ExchangeContext?, message: ByteArray?) {
        ctx?.errorCode(1)
    }
}
