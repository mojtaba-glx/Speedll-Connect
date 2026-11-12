package app.speedll.connect

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import io.nekohasekai.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

object DefaultNetworkMonitor {
    private const val TAG = "SpeedllNetworkMonitor"
    private const val LOST_GRACE_DELAY_MS = 450L

    private data class LinkFingerprint(
        val interfaceName: String,
        val addresses: List<String>,
        val dnsServers: List<String>,
        val gateways: List<String>,
    )

    private val callbackThread by lazy {
        HandlerThread("Speedll-NetworkCallback").apply { start() }
    }
    private val callbackHandler by lazy { Handler(callbackThread.looper) }
    private val lock = Any()

    @Volatile
    var defaultNetwork: Network? = null
        private set

    @Volatile
    var isWifiActive: Boolean = false
        private set

    private var listener: InterfaceUpdateListener? = null
    private var service: LibboxVpnService? = null
    private var connectivityManager: ConnectivityManager? = null
    private var registered = false

    private val availableNetworks = LinkedHashMap<Network, NetworkCapabilities>()
    private val usesSingleBestCallback = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    private var lastLinkFingerprint: LinkFingerprint? = null
    private var lastValidated = false
    private var lastMetered = false
    private var hadTransientLoss = false
    private var pendingLostRunnable: Runnable? = null

    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        .build()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val manager = connectivityManager ?: return
            val capabilities = manager.getNetworkCapabilities(network) ?: return
            if (!isPhysicalInternetCapabilities(capabilities)) {
                return
            }
            val linkProperties = manager.getLinkProperties(network)
            synchronized(lock) {
                cancelPendingLostLocked()
                if (usesSingleBestCallback) {
                    availableNetworks.clear()
                }
                availableNetworks[network] = capabilities
                evaluateNetworksLocked(
                    linkPropertiesOverride = if (network == selectBestNetworkLocked()) linkProperties else null,
                )
            }
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            if (!isPhysicalInternetCapabilities(networkCapabilities)) {
                return
            }
            synchronized(lock) {
                if (usesSingleBestCallback && !availableNetworks.containsKey(network)) {
                    return
                }
                cancelPendingLostLocked()
                availableNetworks[network] = networkCapabilities
                evaluateNetworksLocked()
            }
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            val capabilities = connectivityManager?.getNetworkCapabilities(network) ?: return
            if (!isPhysicalInternetCapabilities(capabilities)) {
                return
            }
            synchronized(lock) {
                if (usesSingleBestCallback && !availableNetworks.containsKey(network)) {
                    return
                }
                availableNetworks[network] = capabilities
                evaluateNetworksLocked(
                    linkPropertiesOverride = if (network == selectBestNetworkLocked()) linkProperties else null,
                )
            }
        }

        override fun onLost(network: Network) {
            synchronized(lock) {
                if (usesSingleBestCallback && !availableNetworks.containsKey(network)) {
                    return
                }
                availableNetworks.remove(network)
                val replacement = selectBestNetworkLocked()
                if (replacement != null) {
                    hadTransientLoss = hadTransientLoss || (defaultNetwork == network && replacement != network)
                    evaluateNetworksLocked()
                } else if (defaultNetwork != null) {
                    // Brief grace window prevents momentary Wi-Fi BSSID roaming or
                    // carrier hiccups from flashing defaultNetwork to null mid-roam.
                    hadTransientLoss = true
                    scheduleDelayedLossLocked()
                }
            }
        }
    }

    fun start(context: Context, vpnService: LibboxVpnService) {
        synchronized(lock) {
            cancelPendingLostLocked()
            availableNetworks.clear()
            lastLinkFingerprint = null
            lastValidated = false
            lastMetered = false
            hadTransientLoss = false
            defaultNetwork = null
            isWifiActive = false

            service = vpnService
            connectivityManager =
                context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
                    as? ConnectivityManager
            if (!registered) {
                register()
            }
            seedInitialNetworksLocked()
        }
    }

    fun stop() {
        synchronized(lock) {
            cancelPendingLostLocked()
            unregister()
            availableNetworks.clear()
            lastLinkFingerprint = null
            lastValidated = false
            lastMetered = false
            hadTransientLoss = false
            listener = null
            service = null
            connectivityManager = null
            defaultNetwork = null
            isWifiActive = false
        }
    }

    fun setListener(updateListener: InterfaceUpdateListener?) {
        synchronized(lock) {
            listener = updateListener
            dispatchDefaultInterfaceLocked()
        }
    }

    fun isCurrentNetworkReachable(): Boolean {
        val manager = connectivityManager ?: return false
        val current = defaultNetwork
        if (current != null) {
            val caps = manager.getNetworkCapabilities(current)
            if (caps != null && isPhysicalInternetCapabilities(caps)) {
                return true
            }
        }
        synchronized(lock) {
            return availableNetworks.isNotEmpty()
        }
    }

    fun require(): Network {
        return defaultNetwork ?: error("missing default network")
    }

    private fun seedInitialNetworksLocked() {
        val manager = connectivityManager ?: return
        val activeNetwork = manager.activeNetwork
        val activeCaps = activeNetwork?.let { manager.getNetworkCapabilities(it) }
        if (activeNetwork != null && activeCaps != null && isPhysicalInternetCapabilities(activeCaps)) {
            availableNetworks[activeNetwork] = activeCaps
        }
        for (net in manager.allNetworks) {
            val caps = manager.getNetworkCapabilities(net) ?: continue
            if (isPhysicalInternetCapabilities(caps)) {
                availableNetworks[net] = caps
            }
        }
        val initial = selectBestNetworkLocked()
        if (initial != null) {
            val caps = availableNetworks[initial]
            if (usesSingleBestCallback && caps != null) {
                availableNetworks.clear()
                availableNetworks[initial] = caps
            }
            defaultNetwork = initial
            isWifiActive = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
            lastValidated = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
            lastMetered = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
            lastLinkFingerprint = buildFingerprint(manager.getLinkProperties(initial))
            service?.onPhysicalNetworkUpdated(initial, resetRequired = false)
            dispatchDefaultInterfaceLocked()
        } else {
            isWifiActive = false
        }
    }

    private fun isPhysicalInternetCapabilities(capabilities: NetworkCapabilities): Boolean {
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
            !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    }

    private fun selectBestNetworkLocked(): Network? {
        if (availableNetworks.isEmpty()) return null
        val current = defaultNetwork
        var best: Network? = null
        var bestScore = Int.MIN_VALUE

        for ((network, caps) in availableNetworks) {
            var score = 0
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                score += 1000
            }
            score += when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 300
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 200
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 100
                else -> 50
            }
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)) {
                score += 20
            }
            if (network == current) {
                // Hysteresis prevents flapping on equal-priority updates.
                score += 5
            }
            if (score > bestScore) {
                bestScore = score
                best = network
            }
        }
        return best
    }

    private fun evaluateNetworksLocked(linkPropertiesOverride: LinkProperties? = null) {
        val manager = connectivityManager ?: return
        val next = selectBestNetworkLocked() ?: return
        val caps = availableNetworks[next]
        val linkProperties = linkPropertiesOverride ?: manager.getLinkProperties(next)
        val fingerprint = buildFingerprint(linkProperties)
        val validated = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
        val metered = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false

        val previous = defaultNetwork
        val previousWifi = isWifiActive
        val nextWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val networkSwitched = previous != next
        val linkChangedOnSameNetwork =
            !networkSwitched &&
                lastLinkFingerprint != null &&
                fingerprint != null &&
                fingerprint != lastLinkFingerprint
        val validationRecovered = !networkSwitched && !lastValidated && validated
        val recoveredFromLoss = hadTransientLoss
        val meteredChanged = !networkSwitched && (lastMetered != metered)

        defaultNetwork = next
        isWifiActive = nextWifi
        if (fingerprint != null) {
            lastLinkFingerprint = fingerprint
        }
        lastValidated = validated
        lastMetered = metered
        hadTransientLoss = false

        val resetRequired =
            (previous != null && networkSwitched) ||
                (previous == null && listener != null) ||
                recoveredFromLoss ||
                linkChangedOnSameNetwork ||
                validationRecovered

        if (networkSwitched || resetRequired || previousWifi != nextWifi) {
            service?.onPhysicalNetworkUpdated(next, resetRequired = resetRequired)
        }
        if (networkSwitched || linkChangedOnSameNetwork || meteredChanged || resetRequired) {
            dispatchDefaultInterfaceLocked(linkProperties)
        }
    }

    private fun scheduleDelayedLossLocked() {
        cancelPendingLostLocked()
        val runnable = Runnable {
            synchronized(lock) {
                pendingLostRunnable = null
                if (availableNetworks.isEmpty() && defaultNetwork != null) {
                    defaultNetwork = null
                    isWifiActive = false
                    lastLinkFingerprint = null
                    lastValidated = false
                    lastMetered = false
                    service?.onPhysicalNetworkUpdated(null, resetRequired = false)
                    dispatchDefaultInterfaceLocked()
                } else if (availableNetworks.isNotEmpty()) {
                    evaluateNetworksLocked()
                }
            }
        }
        pendingLostRunnable = runnable
        callbackHandler.postDelayed(runnable, LOST_GRACE_DELAY_MS)
    }

    private fun cancelPendingLostLocked() {
        val existing = pendingLostRunnable ?: return
        callbackHandler.removeCallbacks(existing)
        pendingLostRunnable = null
    }

    private fun buildFingerprint(linkProperties: LinkProperties?): LinkFingerprint? {
        if (linkProperties == null) return null
        val iface = linkProperties.interfaceName ?: return null
        val addresses = linkProperties.linkAddresses
            .map { "${it.address.hostAddress}/${it.prefixLength}" }
            .sorted()
        val dns = linkProperties.dnsServers
            .mapNotNull { it.hostAddress }
            .sorted()
        val gateways = linkProperties.routes
            .filter { it.destination.prefixLength == 0 }
            .mapNotNull { it.gateway?.hostAddress }
            .sorted()
        return LinkFingerprint(iface, addresses, dns, gateways)
    }

    private fun register() {
        val manager = connectivityManager ?: return
        try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                    manager.registerBestMatchingNetworkCallback(request, callback, callbackHandler)

                else ->
                    manager.registerNetworkCallback(request, callback, callbackHandler)
            }
            registered = true
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register network callback: ${e.javaClass.simpleName}")
        }
    }

    private fun unregister() {
        val manager = connectivityManager
        if (manager != null && registered) {
            try {
                manager.unregisterNetworkCallback(callback)
            } catch (_: Exception) {
            }
        }
        registered = false
    }

    private fun dispatchDefaultInterfaceLocked(linkPropertiesOverride: LinkProperties? = null) {
        val updateListener = listener ?: return
        val network = defaultNetwork
        if (network == null) {
            updateListener.updateDefaultInterface("", -1, false, false)
            return
        }

        try {
            val manager = connectivityManager ?: return
            val linkProperties = linkPropertiesOverride ?: manager.getLinkProperties(network) ?: return
            val interfaceName = linkProperties.interfaceName ?: return
            if (interfaceName.startsWith("tun")) {
                Log.w(TAG, "Refusing to dispatch TUN interface as default: $interfaceName")
                return
            }
            val interfaceIndex = try {
                NetworkInterface.getByName(interfaceName)?.index ?: -1
            } catch (_: Exception) {
                -1
            }
            val isExpensive = availableNetworks[network]
                ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
            updateListener.updateDefaultInterface(
                interfaceName,
                interfaceIndex,
                isExpensive,
                false,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not dispatch default interface: ${e.javaClass.simpleName}")
        }
    }
}
