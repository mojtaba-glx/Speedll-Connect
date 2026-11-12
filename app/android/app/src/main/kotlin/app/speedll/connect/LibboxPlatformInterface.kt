package app.speedll.connect

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Process
import android.system.OsConstants
import android.util.Log
import io.nekohasekai.libbox.BridgeOptions
import io.nekohasekai.libbox.BridgeSession
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.PlatformUser
import io.nekohasekai.libbox.RoutePrefix
import io.nekohasekai.libbox.RoutePrefixIterator
import io.nekohasekai.libbox.ShellSession
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface
import java.net.NetworkInterface as JavaNetworkInterface

class LibboxPlatformInterface(
    private val service: LibboxVpnService,
) : PlatformInterface {
    private companion object {
        const val TAG = "SpeedllLibboxPlatform"
    }

    private val context: Context
        get() = service.applicationContext

    private val connectivityManager: ConnectivityManager?
        get() = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private val packageManager: PackageManager
        get() = context.packageManager

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        if (fd > 0 && !service.protect(fd)) {
            Log.w(TAG, "android: protect failed for socket fd=$fd")
        }
    }

    override fun openTun(options: TunOptions): Int {
        if (VpnService.prepare(service) != null) {
            error("android: missing vpn permission")
        }

        val builder = service.newTunBuilder()
            .setSession("Speedll Connect")
            .setMtu(options.mtu)

        if (service.isKillSwitchEnabled || options.strictRoute) {
            try {
                builder.setBlocking(true)
            } catch (e: Exception) {
                Log.w(TAG, "Could not enable blocking mode: ${e.javaClass.simpleName}")
            }
        }

        addAddresses(options.inet4Address, builder)
        addAddresses(options.inet6Address, builder)

        if (options.autoRoute) {
            var dnsCount = 0
            val dnsMode = options.dnsMode?.value
            if (dnsMode != Libbox.DNSModeDisabled) {
                try {
                    val dnsServers = options.dnsServerAddress
                    while (dnsServers.hasNext()) {
                        val dns = dnsServers.next()
                        if (dns.isNotBlank()) {
                            builder.addDnsServer(dns)
                            dnsCount++
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed reading dnsServerAddress: ${e.message}")
                }
            }
            if (dnsCount == 0) {
                builder.addDnsServer("172.19.0.2")
                builder.addDnsServer("1.1.1.1")
            }

            var hasV4Route = false
            try {
                val inet4Routes = options.inet4RouteAddress
                while (inet4Routes.hasNext()) {
                    val route = inet4Routes.next()
                    try {
                        builder.addRoute(route.address(), route.prefix())
                        hasV4Route = true
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to add IPv4 route ${route.address()}/${route.prefix()}: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed reading inet4RouteAddress: ${e.message}")
            }

            if (!hasV4Route) {
                builder.addRoute("0.0.0.0", 0)
            }

            var hasV6Route = false
            try {
                val inet6Routes = options.inet6RouteAddress
                while (inet6Routes.hasNext()) {
                    val route = inet6Routes.next()
                    try {
                        builder.addRoute(route.address(), route.prefix())
                        hasV6Route = true
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to add IPv6 route ${route.address()}/${route.prefix()}: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed reading inet6RouteAddress: ${e.message}")
            }

            if (!hasV6Route) {
                try {
                    builder.addRoute("::", 0)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to add default IPv6 route: ${e.message}")
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                try {
                    val excludedInet4Routes = options.inet4RouteExcludeAddress
                    while (excludedInet4Routes.hasNext()) {
                        builder.excludeRoute(excludedInet4Routes.next().toIpPrefix())
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed excluding IPv4 route: ${e.message}")
                }

                try {
                    val excludedInet6Routes = options.inet6RouteExcludeAddress
                    while (excludedInet6Routes.hasNext()) {
                        builder.excludeRoute(excludedInet6Routes.next().toIpPrefix())
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed excluding IPv6 route: ${e.message}")
                }
            }

            addPackages(options.includePackage, builder, allow = true)
            addPackages(options.excludePackage, builder, allow = false)
        }

        try {
            builder.addDisallowedApplication(service.packageName)
        } catch (e: Exception) {
            Log.w(TAG, "Could not exclude own package: ${e.javaClass.simpleName}")
        }

        val interfaceDescriptor = builder.establish()
            ?: error("android: the application is not prepared or is revoked")
        service.onTunEstablished(interfaceDescriptor)
        return interfaceDescriptor.fd
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.start(context, service)
        DefaultNetworkMonitor.setListener(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(null)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        try {
            val manager = connectivityManager
            if (manager != null) {
                for (network in manager.allNetworks) {
                    val capabilities = manager.getNetworkCapabilities(network) ?: continue
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                    val linkProperties = manager.getLinkProperties(network) ?: continue
                    val interfaceName = linkProperties.interfaceName ?: continue
                    val javaInterface = try {
                        JavaNetworkInterface.getByName(interfaceName)
                    } catch (_: Exception) {
                        null
                    } ?: continue

                    val boxInterface = LibboxNetworkInterface()
                    boxInterface.name = interfaceName
                    boxInterface.index = javaInterface.index
                    boxInterface.mtu = try {
                        javaInterface.mtu
                    } catch (_: Exception) {
                        1500
                    }
                    boxInterface.addresses = StringArray(
                        javaInterface.interfaceAddresses.mapNotNull { address ->
                            val inetAddress = address.address ?: return@mapNotNull null
                            val hostAddress = if (inetAddress is Inet6Address) {
                                Inet6Address.getByAddress(null, inetAddress.address, null).hostAddress
                            } else {
                                inetAddress.hostAddress
                            }
                            "$hostAddress/${address.networkPrefixLength}"
                        }.iterator(),
                    )
                    boxInterface.dnsServer = StringArray(
                        linkProperties.dnsServers.mapNotNull { it.hostAddress }.iterator(),
                    )
                    boxInterface.gateway = StringArray(
                        linkProperties.routes
                            .filter { it.destination.prefixLength == 0 }
                            .mapNotNull { it.gateway }
                            .filterNot { it.isAnyLocalAddress }
                            .mapNotNull { it.hostAddress }
                            .iterator(),
                    )
                    boxInterface.type = when {
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ->
                            Libbox.InterfaceTypeWIFI

                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
                            Libbox.InterfaceTypeCellular

                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
                            Libbox.InterfaceTypeEthernet

                        else -> Libbox.InterfaceTypeOther
                    }
                    boxInterface.flags = buildInterfaceFlags(javaInterface)
                    boxInterface.metered =
                        !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                    interfaces.add(boxInterface)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not enumerate interfaces: ${e.javaClass.simpleName}")
        }
        return NetworkInterfaceArray(interfaces.iterator())
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        val owner = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val manager = connectivityManager
            val uid = if (manager != null) {
                try {
                    manager.getConnectionOwnerUid(
                        ipProtocol,
                        InetSocketAddress(sourceAddress, sourcePort),
                        InetSocketAddress(destinationAddress, destinationPort),
                    )
                } catch (_: Exception) {
                    Process.INVALID_UID
                }
            } else {
                Process.INVALID_UID
            }
            if (uid != Process.INVALID_UID) {
                ConnectionOwner().apply { userId = uid }
            } else {
                try {
                    Libbox.findConnectionOwner(
                        ipProtocol,
                        sourceAddress,
                        sourcePort,
                        destinationAddress,
                        destinationPort,
                    )
                } catch (_: Exception) {
                    ConnectionOwner().apply { userId = Process.INVALID_UID }
                }
            }
        } else {
            try {
                Libbox.findConnectionOwner(
                    ipProtocol,
                    sourceAddress,
                    sourcePort,
                    destinationAddress,
                    destinationPort,
                )
            } catch (_: Exception) {
                ConnectionOwner().apply { userId = Process.INVALID_UID }
            }
        }

        val packageNames = try {
            packageManager.getPackagesForUid(owner.userId)
        } catch (_: Exception) {
            null
        }
        owner.userName = packageNames?.firstOrNull().orEmpty()
        owner.setAndroidPackageNames(
            StringArray(packageNames?.iterator() ?: emptyList<String>().iterator()),
        )
        return owner
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun clearDNSCache() {
    }

    override fun readWIFIState(): WIFIState? = null

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun startNeighborMonitor(listener: NeighborUpdateListener) {
    }

    override fun closeNeighborMonitor(listener: NeighborUpdateListener) {
    }

    override fun usePlatformShell(): Boolean = false

    override fun checkPlatformShell() {
        error("android: platform shell is not supported")
    }

    override fun lookupUser(username: String): PlatformUser {
        error("android: user lookup is not supported")
    }

    override fun openShellSession(
        user: PlatformUser,
        command: String,
        environ: StringIterator,
        term: String,
        rows: Int,
        cols: Int,
    ): ShellSession {
        error("android: shell sessions are not supported")
    }

    override fun readSystemSSHHostKey(): String {
        error("android: system SSH host key is not supported")
    }

    override fun lookupSFTPServer(): String {
        error("android: SFTP lookup is not supported")
    }

    override fun tailscaleHostname(): String {
        return "${Build.MANUFACTURER} ${Build.MODEL}".trim()
    }

    override fun usePlatformBridge(): Boolean = false

    override fun createBridge(options: BridgeOptions): BridgeSession {
        error("android: bridge mode is not supported")
    }

    override fun registerMyInterface(name: String) {
    }

    override fun sendNotification(notification: io.nekohasekai.libbox.Notification) {
    }

    override fun cancelNotification(identifier: String, typeID: Int) {
    }

    private fun addAddresses(iterator: RoutePrefixIterator, builder: VpnService.Builder) {
        while (iterator.hasNext()) {
            val address = iterator.next()
            builder.addAddress(address.address(), address.prefix())
        }
    }

    private fun addRoutes(iterator: RoutePrefixIterator, builder: VpnService.Builder) {
        while (iterator.hasNext()) {
            val route = iterator.next()
            builder.addRoute(route.address(), route.prefix())
        }
    }

    private fun addPackages(iterator: StringIterator, builder: VpnService.Builder, allow: Boolean) {
        while (iterator.hasNext()) {
            val packageName = iterator.next()
            if (packageName == service.packageName) continue
            try {
                if (allow) {
                    builder.addAllowedApplication(packageName)
                } else {
                    builder.addDisallowedApplication(packageName)
                }
            } catch (_: PackageManager.NameNotFoundException) {
            }
        }
    }

    private fun buildInterfaceFlags(javaInterface: JavaNetworkInterface): Int {
        var flags = 0
        if (javaInterface.isUp) flags = flags or OsConstants.IFF_UP
        if (javaInterface.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK
        if (javaInterface.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
        if (javaInterface.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
        return flags
    }

    private fun RoutePrefix.toIpPrefix(): IpPrefix {
        return IpPrefix(InetAddress.getByName(address()), prefix())
    }

    private class StringArray(
        private val iterator: Iterator<String>,
    ) : StringIterator {
        override fun len(): Int = 0
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): String = iterator.next()
    }

    private class NetworkInterfaceArray(
        private val iterator: Iterator<LibboxNetworkInterface>,
    ) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()
        override fun next(): LibboxNetworkInterface = iterator.next()
    }
}
