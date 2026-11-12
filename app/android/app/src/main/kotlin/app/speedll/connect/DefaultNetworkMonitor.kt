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

    private val callbackThread by lazy {
        HandlerThread("Speedll-NetworkCallback").apply { start() }
    }
    private val callbackHandler by lazy { Handler(callbackThread.looper) }
    private val lock = Any()

    @Volatile
    var defaultNetwork: Network? = null
        private set

    private var listener: InterfaceUpdateListener? = null
    private var service: LibboxVpnService? = null
    private var connectivityManager: ConnectivityManager? = null
    private var registered = false

    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        .build()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val capabilities = connectivityManager?.getNetworkCapabilities(network) ?: return
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            ) {
                return
            }
            updateNetwork(network)
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            if (networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                !networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            ) {
                return
            }
            updateNetwork(network)
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            val capabilities = connectivityManager?.getNetworkCapabilities(network) ?: return
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            ) {
                return
            }
            updateNetwork(network)
        }

        override fun onLost(network: Network) {
            if (defaultNetwork == network) {
                updateNetwork(null)
            }
        }
    }

    fun start(context: Context, vpnService: LibboxVpnService) {
        synchronized(lock) {
            service = vpnService
            connectivityManager =
                context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)
                    as? ConnectivityManager
            if (!registered) {
                register()
            }
            val activeNetwork = connectivityManager?.activeNetwork
            val activeCapabilities = activeNetwork?.let {
                connectivityManager?.getNetworkCapabilities(it)
            }
            if (activeCapabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) == true &&
                !activeCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            ) {
                updateNetwork(activeNetwork)
            } else {
                val physicalNetwork = connectivityManager?.allNetworks?.firstOrNull { net ->
                    val caps = connectivityManager?.getNetworkCapabilities(net)
                    caps != null &&
                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
                        !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                }
                if (physicalNetwork != null) {
                    updateNetwork(physicalNetwork)
                }
            }
        }
    }

    fun stop() {
        synchronized(lock) {
            unregister()
            listener = null
            service = null
            connectivityManager = null
            defaultNetwork = null
        }
    }

    fun setListener(updateListener: InterfaceUpdateListener?) {
        synchronized(lock) {
            listener = updateListener
            dispatchDefaultInterface()
        }
    }

    fun require(): Network {
        return defaultNetwork ?: error("missing default network")
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
            Log.w(TAG, "Could not register network monitor: ${e.javaClass.simpleName}")
            registered = false
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

    private fun updateNetwork(network: Network?) {
        val previous = defaultNetwork
        defaultNetwork = network
        if (previous != network) {
            service?.onPhysicalNetworkChanged(network)
        }
        dispatchDefaultInterface()
    }

    private fun dispatchDefaultInterface() {
        val updateListener = listener ?: return
        val network = defaultNetwork
        if (network == null) {
            updateListener.updateDefaultInterface("", -1, false, false)
            return
        }

        try {
            val manager = connectivityManager ?: return
            val linkProperties = manager.getLinkProperties(network) ?: return
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
            updateListener.updateDefaultInterface(
                interfaceName,
                interfaceIndex,
                false,
                false,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not dispatch default interface: ${e.javaClass.simpleName}")
        }
    }
}
