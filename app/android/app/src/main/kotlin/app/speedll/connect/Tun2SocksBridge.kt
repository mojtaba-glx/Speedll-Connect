package app.speedll.connect

import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * User-space TUN-to-SOCKS5 and UDP DNS packet bridge for unrooted Android VpnService.
 *
 * Reads raw IPv4 packets from the Android VpnService TUN descriptor, translates:
 * - TCP flows into SOCKS5 CONNECT streams towards sing-box's local mixed inbound (127.0.0.1:2080)
 * - UDP DNS queries (port 53) into sing-box's local direct DNS inbound (127.0.0.1:2053)
 * - Other UDP datagrams via SOCKS5 UDP ASSOCIATE (127.0.0.1:2080)
 * - ICMP Echo requests into immediate ICMP Echo replies
 */
class Tun2SocksBridge(
    private val vpnInterface: ParcelFileDescriptor,
    private val socksHost: String = "127.0.0.1",
    private val socksPort: Int = 2080,
    private val dnsPort: Int = 2053
) {
    companion object {
        private const val TAG = "Tun2SocksBridge"
        private const val MAX_PACKET_SIZE = 32768
        private const val TCP_MSS = 1360
        private const val TCP_WINDOW_SIZE = 65535

        private const val PROTO_ICMP = 1
        private const val PROTO_TCP = 6
        private const val PROTO_UDP = 17

        private const val TCP_FIN = 0x01
        private const val TCP_SYN = 0x02
        private const val TCP_RST = 0x04
        private const val TCP_PSH = 0x08
        private const val TCP_ACK = 0x10
    }

    private val running = AtomicBoolean(false)
    private val ipIdCounter = AtomicInteger(1)
    private val tunWriteLock = Any()

    private var tunIn: FileInputStream? = null
    private var tunOut: FileOutputStream? = null
    private var readerThread: Thread? = null
    private val ioExecutor: ExecutorService = Executors.newCachedThreadPool()

    private data class FlowKey(
        val srcIp: Int,
        val srcPort: Int,
        val dstIp: Int,
        val dstPort: Int
    )

    private data class CachedDnsEntry(
        val response: ByteArray,
        val expiresAtMs: Long
    )

    private val tcpSessions = ConcurrentHashMap<FlowKey, TcpSession>()
    private val dnsCache = ConcurrentHashMap<String, CachedDnsEntry>()

    fun start() {
        if (!running.compareAndSet(false, true)) return

        tunIn = FileInputStream(vpnInterface.fileDescriptor)
        tunOut = FileOutputStream(vpnInterface.fileDescriptor)

        readerThread = Thread({
            val buffer = ByteArray(MAX_PACKET_SIZE)
            Log.i(TAG, "Tun2SocksBridge packet loop started")
            while (running.get()) {
                try {
                    val length = tunIn?.read(buffer) ?: break
                    if (length <= 0) continue
                    handleOutgoingIpPacket(buffer, length)
                } catch (e: Exception) {
                    if (running.get()) {
                        Log.w(TAG, "TUN read error: ${e.message}")
                    }
                    break
                }
            }
            Log.i(TAG, "Tun2SocksBridge packet loop stopped")
        }, "Speedll-TunReader").apply {
            isDaemon = true
            start()
        }
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) return

        for ((key, session) in tcpSessions) {
            session.closeSilently()
            tcpSessions.remove(key)
        }
        dnsCache.clear()

        try {
            readerThread?.interrupt()
        } catch (_: Exception) {
        }

        ioExecutor.shutdownNow()
    }

    private fun writeToTun(packet: ByteArray) {
        if (!running.get()) return
        synchronized(tunWriteLock) {
            try {
                tunOut?.write(packet)
                tunOut?.flush()
            } catch (e: Exception) {
                if (running.get()) {
                    Log.w(TAG, "TUN write error: ${e.message}")
                }
            }
        }
    }

    private fun handleOutgoingIpPacket(packet: ByteArray, length: Int) {
        if (length < 20) return
        val version = (packet[0].toInt() ushr 4) and 0x0F
        if (version != 4) return

        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (ihl < 20 || length < ihl) return

        val totalLen = readUint16(packet, 2).coerceAtMost(length)
        if (totalLen < ihl) return

        val protocol = packet[9].toInt() and 0xFF
        val srcIp = readInt32(packet, 12)
        val dstIp = readInt32(packet, 16)

        when (protocol) {
            PROTO_TCP -> handleTcpPacket(packet, ihl, totalLen, srcIp, dstIp)
            PROTO_UDP -> handleUdpPacket(packet, ihl, totalLen, srcIp, dstIp)
            PROTO_ICMP -> handleIcmpPacket(packet, ihl, totalLen, srcIp, dstIp)
        }
    }

    private fun handleIcmpPacket(
        packet: ByteArray,
        ihl: Int,
        totalLen: Int,
        srcIp: Int,
        dstIp: Int
    ) {
        if (totalLen < ihl + 8) return
        val icmpType = packet[ihl].toInt() and 0xFF
        val icmpCode = packet[ihl + 1].toInt() and 0xFF
        // Echo Request (Type 8, Code 0) -> Echo Reply (Type 0, Code 0)
        if (icmpType == 8 && icmpCode == 0) {
            val icmpLen = totalLen - ihl
            val reply = ByteArray(20 + icmpLen)
            writeIpv4Header(reply, PROTO_ICMP, dstIp, srcIp, 20 + icmpLen)
            System.arraycopy(packet, ihl, reply, 20, icmpLen)
            reply[20] = 0 // Type 0: Echo Reply
            reply[22] = 0
            reply[23] = 0
            val csum = computeOnesComplementChecksum(reply, 20, icmpLen)
            writeUint16(reply, 22, csum)
            writeToTun(reply)
        }
    }

    private fun handleUdpPacket(
        packet: ByteArray,
        ihl: Int,
        totalLen: Int,
        srcIp: Int,
        dstIp: Int
    ) {
        if (totalLen < ihl + 8) return
        val srcPort = readUint16(packet, ihl)
        val dstPort = readUint16(packet, ihl + 2)
        val udpLen = readUint16(packet, ihl + 4)
        val payloadOffset = ihl + 8
        val payloadLen = (totalLen - payloadOffset).coerceAtMost(udpLen - 8)
        if (payloadLen <= 0) return

        val payload = packet.copyOfRange(payloadOffset, payloadOffset + payloadLen)

        if (dstPort == 53) {
            ioExecutor.execute {
                forwardDnsQuery(srcIp, srcPort, dstIp, dstPort, payload)
            }
        } else {
            ioExecutor.execute {
                forwardUdpViaSocks5(srcIp, srcPort, dstIp, dstPort, payload)
            }
        }
    }

    private fun buildDnsCacheKey(queryPayload: ByteArray): String? {
        if (queryPayload.size <= 12) return null
        val end = queryPayload.size.coerceAtMost(96)
        val sb = StringBuilder((end - 2) * 2)
        for (i in 2 until end) {
            val b = queryPayload[i].toInt() and 0xFF
            sb.append(Character.forDigit((b ushr 4) and 0x0F, 16))
            sb.append(Character.forDigit(b and 0x0F, 16))
        }
        return sb.toString()
    }

    private fun forwardDnsQuery(
        clientIp: Int,
        clientPort: Int,
        dnsServerIp: Int,
        dnsServerPort: Int,
        queryPayload: ByteArray
    ) {
        val now = System.currentTimeMillis()
        val cacheKey = buildDnsCacheKey(queryPayload)
        if (cacheKey != null) {
            val cached = dnsCache[cacheKey]
            if (cached != null) {
                if (now < cached.expiresAtMs && cached.response.size >= 12) {
                    val replyCopy = cached.response.copyOf()
                    replyCopy[0] = queryPayload[0]
                    replyCopy[1] = queryPayload[1]
                    val ipPacket = buildUdpIpPacket(
                        srcIp = dnsServerIp,
                        srcPort = dnsServerPort,
                        dstIp = clientIp,
                        dstPort = clientPort,
                        payload = replyCopy
                    )
                    writeToTun(ipPacket)
                    return
                } else {
                    dnsCache.remove(cacheKey)
                }
            }
        }

        val loopback = try {
            InetAddress.getByName(socksHost)
        } catch (_: Exception) {
            return
        }

        for (attempt in 1..2) {
            if (!running.get()) return
            var socket: DatagramSocket? = null
            try {
                socket = DatagramSocket()
                socket.soTimeout = if (attempt == 1) 2500 else 3500
                val outPacket = DatagramPacket(queryPayload, queryPayload.size, loopback, dnsPort)
                socket.send(outPacket)

                val responseBuf = ByteArray(4096)
                val inPacket = DatagramPacket(responseBuf, responseBuf.size)
                socket.receive(inPacket)

                if (inPacket.length > 0) {
                    val dnsReply = responseBuf.copyOfRange(0, inPacket.length)
                    if (cacheKey != null && dnsReply.size >= 12 && (dnsReply[3].toInt() and 0x0F) == 0) {
                        if (dnsCache.size > 512) {
                            dnsCache.clear()
                        }
                        dnsCache[cacheKey] = CachedDnsEntry(
                            response = dnsReply.copyOf(),
                            expiresAtMs = System.currentTimeMillis() + 45_000L
                        )
                    }
                    val ipPacket = buildUdpIpPacket(
                        srcIp = dnsServerIp,
                        srcPort = dnsServerPort,
                        dstIp = clientIp,
                        dstPort = clientPort,
                        payload = dnsReply
                    )
                    writeToTun(ipPacket)
                    return
                }
            } catch (e: Exception) {
                if (attempt == 2) {
                    Log.d(TAG, "DNS forward timeout/error after 2 attempts: ${e.message}")
                }
            } finally {
                try {
                    socket?.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun forwardUdpViaSocks5(
        clientIp: Int,
        clientPort: Int,
        targetIp: Int,
        targetPort: Int,
        payload: ByteArray
    ) {
        var controlSocket: Socket? = null
        var udpSocket: DatagramSocket? = null
        try {
            controlSocket = Socket()
            controlSocket.connect(InetSocketAddress(socksHost, socksPort), 4000)
            controlSocket.soTimeout = 5000
            val sockIn = controlSocket.getInputStream()
            val sockOut = controlSocket.getOutputStream()

            // SOCKS5 greeting (no auth)
            sockOut.write(byteArrayOf(0x05, 0x01, 0x00))
            sockOut.flush()
            val greetResp = ByteArray(2)
            if (!readFully(sockIn, greetResp) || greetResp[0] != 0x05.toByte() || greetResp[1] != 0x00.toByte()) {
                return
            }

            // SOCKS5 UDP ASSOCIATE request: 0x05 0x03 0x00 0x01 0.0.0.0:0
            sockOut.write(
                byteArrayOf(
                    0x05, 0x03, 0x00, 0x01,
                    0x00, 0x00, 0x00, 0x00,
                    0x00, 0x00
                )
            )
            sockOut.flush()

            val assocHead = ByteArray(4)
            if (!readFully(sockIn, assocHead) || assocHead[1] != 0x00.toByte()) {
                return
            }

            val atyp = assocHead[3].toInt() and 0xFF
            val addrBytesLen = when (atyp) {
                0x01 -> 4
                0x04 -> 16
                0x03 -> (sockIn.read() and 0xFF)
                else -> return
            }
            val boundAddrBytes = ByteArray(addrBytesLen)
            if (!readFully(sockIn, boundAddrBytes)) return
            val portBytes = ByteArray(2)
            if (!readFully(sockIn, portBytes)) return
            val relayPort = ((portBytes[0].toInt() and 0xFF) shl 8) or (portBytes[1].toInt() and 0xFF)
            if (relayPort <= 0) return

            udpSocket = DatagramSocket()
            udpSocket.soTimeout = 4000

            // Build SOCKS5 UDP frame: RSV(2)=0, FRAG(1)=0, ATYP(1)=1, DST.ADDR(4), DST.PORT(2), DATA
            val socksUdpFrame = ByteArray(10 + payload.size)
            socksUdpFrame[3] = 0x01
            writeInt32(socksUdpFrame, 4, targetIp)
            writeUint16(socksUdpFrame, 8, targetPort)
            System.arraycopy(payload, 0, socksUdpFrame, 10, payload.size)

            val relayAddress = InetAddress.getByName(socksHost)
            udpSocket.send(DatagramPacket(socksUdpFrame, socksUdpFrame.size, relayAddress, relayPort))

            val recvBuf = ByteArray(4096)
            val recvPacket = DatagramPacket(recvBuf, recvBuf.size)
            udpSocket.receive(recvPacket)

            if (recvPacket.length > 10 && recvBuf[2] == 0x00.toByte()) {
                val respAtyp = recvBuf[3].toInt() and 0xFF
                val headerLen = when (respAtyp) {
                    0x01 -> 10
                    0x04 -> 22
                    0x03 -> 7 + (recvBuf[4].toInt() and 0xFF)
                    else -> return
                }
                if (recvPacket.length > headerLen) {
                    val udpPayload = recvBuf.copyOfRange(headerLen, recvPacket.length)
                    val ipReply = buildUdpIpPacket(
                        srcIp = targetIp,
                        srcPort = targetPort,
                        dstIp = clientIp,
                        dstPort = clientPort,
                        payload = udpPayload
                    )
                    writeToTun(ipReply)
                }
            }
        } catch (_: Exception) {
        } finally {
            try {
                udpSocket?.close()
            } catch (_: Exception) {
            }
            try {
                controlSocket?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun handleTcpPacket(
        packet: ByteArray,
        ihl: Int,
        totalLen: Int,
        srcIp: Int,
        dstIp: Int
    ) {
        if (totalLen < ihl + 20) return
        val srcPort = readUint16(packet, ihl)
        val dstPort = readUint16(packet, ihl + 2)
        val seqNum = readUint32(packet, ihl + 4)
        val ackNum = readUint32(packet, ihl + 8)
        val dataOffset = ((packet[ihl + 12].toInt() ushr 4) and 0x0F) * 4
        val flags = packet[ihl + 13].toInt() and 0xFF

        if (dataOffset < 20 || totalLen < ihl + dataOffset) return
        val payloadOffset = ihl + dataOffset
        val payloadLen = totalLen - payloadOffset

        val key = FlowKey(srcIp, srcPort, dstIp, dstPort)
        val isSyn = (flags and TCP_SYN) != 0
        val isAck = (flags and TCP_ACK) != 0
        val isFin = (flags and TCP_FIN) != 0
        val isRst = (flags and TCP_RST) != 0

        if (isRst) {
            tcpSessions.remove(key)?.closeSilently()
            return
        }

        if (isSyn && !isAck) {
            val existing = tcpSessions[key]
            if (existing != null && existing.clientIsn == seqNum) {
                existing.resendSynAck()
                return
            }
            existing?.closeSilently()
            val session = TcpSession(key, seqNum)
            tcpSessions[key] = session
            session.start()
            return
        }

        val session = tcpSessions[key]
        if (session == null) {
            // Unknown flow: reply with RST so the client reconnects cleanly
            val rstPacket = buildTcpIpPacket(
                srcIp = dstIp,
                srcPort = dstPort,
                dstIp = srcIp,
                dstPort = srcPort,
                seq = ackNum,
                ack = (seqNum + payloadLen.toLong().coerceAtLeast(1L)) and 0xFFFFFFFFL,
                flags = TCP_RST or TCP_ACK,
                payload = ByteArray(0)
            )
            writeToTun(rstPacket)
            return
        }

        val payload = if (payloadLen > 0) {
            packet.copyOfRange(payloadOffset, payloadOffset + payloadLen)
        } else {
            ByteArray(0)
        }

        session.onClientSegment(seqNum, ackNum, flags, payload, isFin)
    }

    private inner class TcpSession(
        val key: FlowKey,
        val clientIsn: Long
    ) {
        private val closed = AtomicBoolean(false)
        private val outboundQueue = LinkedBlockingQueue<ByteArray>()
        private val poisonPill = ByteArray(0)

        @Volatile
        var clientNextSeq: Long = (clientIsn + 1L) and 0xFFFFFFFFL

        @Volatile
        var serverSeq: Long = 0x20000000L

        private val synAckSeq: Long = serverSeq
        private var socksSocket: Socket? = null

        fun start() {
            // Advance serverSeq for SYN
            serverSeq = (serverSeq + 1L) and 0xFFFFFFFFL
            sendSynAck()

            ioExecutor.execute {
                runSocksRelay()
            }
        }

        fun resendSynAck() {
            sendSynAck()
        }

        private fun sendSynAck() {
            // TCP MSS option (4 bytes: Kind=2, Len=4, MSS=1360)
            val mssOption = byteArrayOf(
                0x02,
                0x04,
                ((TCP_MSS ushr 8) and 0xFF).toByte(),
                (TCP_MSS and 0xFF).toByte()
            )
            val pkt = buildTcpIpPacket(
                srcIp = key.dstIp,
                srcPort = key.dstPort,
                dstIp = key.srcIp,
                dstPort = key.srcPort,
                seq = synAckSeq,
                ack = clientNextSeq,
                flags = TCP_SYN or TCP_ACK,
                payload = ByteArray(0),
                tcpOptions = mssOption
            )
            writeToTun(pkt)
        }

        @Synchronized
        fun onClientSegment(
            seq: Long,
            @Suppress("UNUSED_PARAMETER") ack: Long,
            @Suppress("UNUSED_PARAMETER") flags: Int,
            payload: ByteArray,
            isFin: Boolean
        ) {
            if (closed.get()) return

            if (payload.isNotEmpty()) {
                if (seq == clientNextSeq) {
                    clientNextSeq = (clientNextSeq + payload.size.toLong()) and 0xFFFFFFFFL
                    sendAck(TCP_ACK)
                    outboundQueue.offer(payload)
                } else {
                    // Out-of-order or retransmitted segment: send current ACK so kernel aligns
                    sendAck(TCP_ACK)
                    return
                }
            }

            if (isFin) {
                if (seq == clientNextSeq || (payload.isNotEmpty() && ((seq + payload.size.toLong()) and 0xFFFFFFFFL) == clientNextSeq)) {
                    clientNextSeq = (clientNextSeq + 1L) and 0xFFFFFFFFL
                }
                sendAck(TCP_FIN or TCP_ACK)
                serverSeq = (serverSeq + 1L) and 0xFFFFFFFFL
                outboundQueue.offer(poisonPill)
                closeSilently()
                tcpSessions.remove(key, this)
            }
        }

        private fun sendAck(flags: Int) {
            val pkt = buildTcpIpPacket(
                srcIp = key.dstIp,
                srcPort = key.dstPort,
                dstIp = key.srcIp,
                dstPort = key.srcPort,
                seq = serverSeq,
                ack = clientNextSeq,
                flags = flags,
                payload = ByteArray(0)
            )
            writeToTun(pkt)
        }

        private fun sendRstAndClose() {
            if (!closed.get()) {
                val pkt = buildTcpIpPacket(
                    srcIp = key.dstIp,
                    srcPort = key.dstPort,
                    dstIp = key.srcIp,
                    dstPort = key.srcPort,
                    seq = serverSeq,
                    ack = clientNextSeq,
                    flags = TCP_RST or TCP_ACK,
                    payload = ByteArray(0)
                )
                writeToTun(pkt)
            }
            closeSilently()
            tcpSessions.remove(key, this)
        }

        private fun runSocksRelay() {
            val socket = Socket()
            socksSocket = socket
            try {
                socket.tcpNoDelay = true
                socket.connect(InetSocketAddress(socksHost, socksPort), 6000)
                socket.soTimeout = 10_000

                val sockIn = socket.getInputStream()
                val sockOut = socket.getOutputStream()

                // 1. SOCKS5 Greeting: VER=5, NMETHODS=1, METHOD=0 (No Auth)
                sockOut.write(byteArrayOf(0x05, 0x01, 0x00))
                sockOut.flush()

                val greetResp = ByteArray(2)
                if (!readFully(sockIn, greetResp) ||
                    greetResp[0] != 0x05.toByte() ||
                    greetResp[1] != 0x00.toByte()
                ) {
                    sendRstAndClose()
                    return
                }

                // 2. SOCKS5 CONNECT Request: VER=5, CMD=1 (CONNECT), RSV=0, ATYP=1 (IPv4), DST.ADDR, DST.PORT
                val connectReq = ByteArray(10)
                connectReq[0] = 0x05
                connectReq[1] = 0x01
                connectReq[2] = 0x00
                connectReq[3] = 0x01
                writeInt32(connectReq, 4, key.dstIp)
                writeUint16(connectReq, 8, key.dstPort)
                sockOut.write(connectReq)
                sockOut.flush()

                val respHeader = ByteArray(4)
                if (!readFully(sockIn, respHeader) || respHeader[1] != 0x00.toByte()) {
                    sendRstAndClose()
                    return
                }

                val atyp = respHeader[3].toInt() and 0xFF
                val skipBytes = when (atyp) {
                    0x01 -> 4 + 2
                    0x04 -> 16 + 2
                    0x03 -> (sockIn.read() and 0xFF) + 2
                    else -> {
                        sendRstAndClose()
                        return
                    }
                }
                val rest = ByteArray(skipBytes)
                if (!readFully(sockIn, rest)) {
                    sendRstAndClose()
                    return
                }

                // Handshake complete: remove read timeout so long-lived idle TCP streams
                // (e.g., Telegram, WhatsApp, WebSockets, HTTP/2) never drop prematurely.
                socket.soTimeout = 0
                try {
                    socket.keepAlive = true
                } catch (_: Exception) {
                }

                // 3. Start writer task (Android Client -> SOCKS5 Server)
                ioExecutor.execute {
                    pumpClientToSocks(sockOut)
                }

                // 4. Pump SOCKS5 Server -> Android Client
                val readBuf = ByteArray(TCP_MSS)
                while (running.get() && !closed.get()) {
                    val n = sockIn.read(readBuf)
                    if (n <= 0) break
                    val chunk = readBuf.copyOfRange(0, n)
                    val seqForChunk: Long
                    synchronized(this) {
                        seqForChunk = serverSeq
                        serverSeq = (serverSeq + n.toLong()) and 0xFFFFFFFFL
                    }
                    val dataPkt = buildTcpIpPacket(
                        srcIp = key.dstIp,
                        srcPort = key.dstPort,
                        dstIp = key.srcIp,
                        dstPort = key.srcPort,
                        seq = seqForChunk,
                        ack = clientNextSeq,
                        flags = TCP_PSH or TCP_ACK,
                        payload = chunk
                    )
                    writeToTun(dataPkt)
                }

                // Server closed stream gracefully: send FIN+ACK to client
                if (!closed.get()) {
                    val finSeq: Long
                    synchronized(this) {
                        finSeq = serverSeq
                        serverSeq = (serverSeq + 1L) and 0xFFFFFFFFL
                    }
                    val finPkt = buildTcpIpPacket(
                        srcIp = key.dstIp,
                        srcPort = key.dstPort,
                        dstIp = key.srcIp,
                        dstPort = key.srcPort,
                        seq = finSeq,
                        ack = clientNextSeq,
                        flags = TCP_FIN or TCP_ACK,
                        payload = ByteArray(0)
                    )
                    writeToTun(finPkt)
                }
            } catch (_: Exception) {
                sendRstAndClose()
            } finally {
                closeSilently()
                tcpSessions.remove(key, this)
            }
        }

        private fun pumpClientToSocks(sockOut: OutputStream) {
            try {
                while (running.get() && !closed.get()) {
                    val data = outboundQueue.poll(60, TimeUnit.SECONDS) ?: continue
                    if (data === poisonPill) break
                    if (data.isNotEmpty()) {
                        sockOut.write(data)
                        sockOut.flush()
                    }
                }
            } catch (_: Exception) {
                closeSilently()
            }
        }

        fun closeSilently() {
            if (closed.compareAndSet(false, true)) {
                outboundQueue.offer(poisonPill)
                try {
                    socksSocket?.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun buildUdpIpPacket(
        srcIp: Int,
        srcPort: Int,
        dstIp: Int,
        dstPort: Int,
        payload: ByteArray
    ): ByteArray {
        val udpLen = 8 + payload.size
        val totalLen = 20 + udpLen
        val packet = ByteArray(totalLen)

        writeIpv4Header(packet, PROTO_UDP, srcIp, dstIp, totalLen)

        writeUint16(packet, 20, srcPort)
        writeUint16(packet, 22, dstPort)
        writeUint16(packet, 24, udpLen)
        writeUint16(packet, 26, 0)
        System.arraycopy(payload, 0, packet, 28, payload.size)

        val udpChecksum = computeTransportChecksum(
            packet = packet,
            transportOffset = 20,
            transportLen = udpLen,
            srcIp = srcIp,
            dstIp = dstIp,
            protocol = PROTO_UDP
        )
        writeUint16(packet, 26, if (udpChecksum == 0) 0xFFFF else udpChecksum)
        return packet
    }

    private fun buildTcpIpPacket(
        srcIp: Int,
        srcPort: Int,
        dstIp: Int,
        dstPort: Int,
        seq: Long,
        ack: Long,
        flags: Int,
        payload: ByteArray,
        tcpOptions: ByteArray = ByteArray(0)
    ): ByteArray {
        val tcpHeaderLen = 20 + tcpOptions.size
        val tcpTotalLen = tcpHeaderLen + payload.size
        val totalLen = 20 + tcpTotalLen
        val packet = ByteArray(totalLen)

        writeIpv4Header(packet, PROTO_TCP, srcIp, dstIp, totalLen)

        writeUint16(packet, 20, srcPort)
        writeUint16(packet, 22, dstPort)
        writeUint32(packet, 24, seq)
        writeUint32(packet, 28, ack)
        val dataOffsetWords = tcpHeaderLen / 4
        packet[32] = ((dataOffsetWords shl 4) and 0xF0).toByte()
        packet[33] = (flags and 0xFF).toByte()
        writeUint16(packet, 34, TCP_WINDOW_SIZE)
        writeUint16(packet, 36, 0) // Checksum placeholder
        writeUint16(packet, 38, 0) // Urgent pointer

        if (tcpOptions.isNotEmpty()) {
            System.arraycopy(tcpOptions, 0, packet, 40, tcpOptions.size)
        }
        if (payload.isNotEmpty()) {
            System.arraycopy(payload, 0, packet, 20 + tcpHeaderLen, payload.size)
        }

        val tcpChecksum = computeTransportChecksum(
            packet = packet,
            transportOffset = 20,
            transportLen = tcpTotalLen,
            srcIp = srcIp,
            dstIp = dstIp,
            protocol = PROTO_TCP
        )
        writeUint16(packet, 36, tcpChecksum)
        return packet
    }

    private fun writeIpv4Header(
        packet: ByteArray,
        protocol: Int,
        srcIp: Int,
        dstIp: Int,
        totalLen: Int
    ) {
        packet[0] = 0x45.toByte() // Version 4, IHL 5 (20 bytes)
        packet[1] = 0x00.toByte()
        writeUint16(packet, 2, totalLen)
        writeUint16(packet, 4, ipIdCounter.getAndIncrement() and 0xFFFF)
        writeUint16(packet, 6, 0x4000) // Don't Fragment
        packet[8] = 64.toByte() // TTL
        packet[9] = (protocol and 0xFF).toByte()
        writeUint16(packet, 10, 0) // Header checksum placeholder
        writeInt32(packet, 12, srcIp)
        writeInt32(packet, 16, dstIp)

        val ipChecksum = computeOnesComplementChecksum(packet, 0, 20)
        writeUint16(packet, 10, ipChecksum)
    }

    private fun computeOnesComplementChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0L
        var i = 0
        while (i + 1 < length) {
            val word = ((data[offset + i].toInt() and 0xFF) shl 8) or
                (data[offset + i + 1].toInt() and 0xFF)
            sum += word.toLong()
            i += 2
        }
        if (i < length) {
            sum += ((data[offset + i].toInt() and 0xFF) shl 8).toLong()
        }
        while ((sum ushr 16) != 0L) {
            sum = (sum and 0xFFFFL) + (sum ushr 16)
        }
        return (sum.inv() and 0xFFFFL).toInt()
    }

    private fun computeTransportChecksum(
        packet: ByteArray,
        transportOffset: Int,
        transportLen: Int,
        srcIp: Int,
        dstIp: Int,
        protocol: Int
    ): Int {
        var sum = 0L
        // Pseudo-header: srcIp (32-bit), dstIp (32-bit), zero+proto (16-bit), length (16-bit)
        sum += ((srcIp ushr 16) and 0xFFFF).toLong()
        sum += (srcIp and 0xFFFF).toLong()
        sum += ((dstIp ushr 16) and 0xFFFF).toLong()
        sum += (dstIp and 0xFFFF).toLong()
        sum += (protocol and 0xFF).toLong()
        sum += (transportLen and 0xFFFF).toLong()

        var i = 0
        while (i + 1 < transportLen) {
            val word = ((packet[transportOffset + i].toInt() and 0xFF) shl 8) or
                (packet[transportOffset + i + 1].toInt() and 0xFF)
            sum += word.toLong()
            i += 2
        }
        if (i < transportLen) {
            sum += ((packet[transportOffset + i].toInt() and 0xFF) shl 8).toLong()
        }
        while ((sum ushr 16) != 0L) {
            sum = (sum and 0xFFFFL) + (sum ushr 16)
        }
        return (sum.inv() and 0xFFFFL).toInt()
    }

    private fun readFully(input: InputStream, buffer: ByteArray): Boolean {
        var offset = 0
        while (offset < buffer.size) {
            val read = input.read(buffer, offset, buffer.size - offset)
            if (read < 0) return false
            offset += read
        }
        return true
    }

    private fun readUint16(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0xFF) shl 8) or (buf[offset + 1].toInt() and 0xFF)
    }

    private fun readInt32(buf: ByteArray, offset: Int): Int {
        return ((buf[offset].toInt() and 0xFF) shl 24) or
            ((buf[offset + 1].toInt() and 0xFF) shl 16) or
            ((buf[offset + 2].toInt() and 0xFF) shl 8) or
            (buf[offset + 3].toInt() and 0xFF)
    }

    private fun readUint32(buf: ByteArray, offset: Int): Long {
        return readInt32(buf, offset).toLong() and 0xFFFFFFFFL
    }

    private fun writeUint16(buf: ByteArray, offset: Int, value: Int) {
        buf[offset] = ((value ushr 8) and 0xFF).toByte()
        buf[offset + 1] = (value and 0xFF).toByte()
    }

    private fun writeInt32(buf: ByteArray, offset: Int, value: Int) {
        buf[offset] = ((value ushr 24) and 0xFF).toByte()
        buf[offset + 1] = ((value ushr 16) and 0xFF).toByte()
        buf[offset + 2] = ((value ushr 8) and 0xFF).toByte()
        buf[offset + 3] = (value and 0xFF).toByte()
    }

    private fun writeUint32(buf: ByteArray, offset: Int, value: Long) {
        writeInt32(buf, offset, (value and 0xFFFFFFFFL).toInt())
    }
}
