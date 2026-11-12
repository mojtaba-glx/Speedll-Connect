package app.speedll.connect

import android.util.Log
import io.nekohasekai.libbox.ExchangeContext
import io.nekohasekai.libbox.LocalDNSTransport
import java.io.InterruptedIOException
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.net.UnknownHostException

class LocalResolver : LocalDNSTransport {
    private companion object {
        const val TAG = "SpeedllLocalResolver"
        const val RCODE_NO_ERROR = 0
        const val RCODE_SERVER_FAILURE = 2
        const val RCODE_NAME_ERROR = 3
    }

    override fun raw(): Boolean = false

    override fun lookup(ctx: ExchangeContext?, network: String?, domain: String?) {
        if (ctx == null) return
        if (domain.isNullOrBlank()) {
            ctx.errorCode(RCODE_NAME_ERROR)
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
                ctx.errorCode(RCODE_NAME_ERROR)
                return
            }

            val family = network?.trim()?.lowercase()
            val filtered = when (family) {
                "ip4", "ipv4" -> addresses.filterIsInstance<Inet4Address>()
                "ip6", "ipv6" -> addresses.filterIsInstance<Inet6Address>()
                else -> addresses.toList()
            }

            if (filtered.isEmpty()) {
                // Domain resolved for another IP family; signal NODATA instead of NXDOMAIN.
                ctx.errorCode(RCODE_NO_ERROR)
                return
            }

            val ips = filtered
                .mapNotNull { it.hostAddress?.substringBefore('%')?.trim() }
                .filter { it.isNotEmpty() }
                .joinToString("\n")

            if (ips.isEmpty()) {
                ctx.errorCode(RCODE_NO_ERROR)
            } else {
                ctx.success(ips)
            }
        } catch (e: UnknownHostException) {
            val detail = "${e.message.orEmpty()} ${e.cause?.message.orEmpty()}".uppercase()
            val transientLookupError =
                !DefaultNetworkMonitor.isCurrentNetworkReachable() ||
                    detail.contains("EAI_AGAIN") ||
                    detail.contains("TRY_AGAIN") ||
                    detail.contains("EAI_FAIL") ||
                    detail.contains("EAI_SYSTEM") ||
                    e.cause is SocketTimeoutException ||
                    e.cause is InterruptedIOException
            if (transientLookupError) {
                // Report SERVFAIL on offline/transient Wi-Fi drops so libbox does
                // not negatively cache the domain as non-existent (NXDOMAIN).
                ctx.errorCode(RCODE_SERVER_FAILURE)
            } else {
                ctx.errorCode(RCODE_NAME_ERROR)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Local DNS lookup failed for $domain ($network): ${e.message}")
            ctx.errorCode(RCODE_SERVER_FAILURE)
        }
    }

    override fun exchange(ctx: ExchangeContext?, message: ByteArray?) {
        ctx?.errorCode(1)
    }
}
