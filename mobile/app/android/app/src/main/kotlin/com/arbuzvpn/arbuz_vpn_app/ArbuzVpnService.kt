package com.arbuzvpn.arbuz_vpn_app

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URI
import java.util.Locale
import kotlin.concurrent.thread

class ArbuzVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var coreProcess: Process? = null
    @Volatile
    private var monitorActive: Boolean = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val protocol = intent.getStringExtra(EXTRA_PROTOCOL)?.uppercase(Locale.US) ?: "N/A"
                val subscriptionUrl = intent.getStringExtra(EXTRA_SUBSCRIPTION_URL).orEmpty()
                val runtimeConfig = intent.getStringExtra(EXTRA_RUNTIME_CONFIG).orEmpty()
                val location = extractLocation(subscriptionUrl)
                thread(start = true, isDaemon = true, name = "arbuz-vpn-connect") {
                    establishTunnel(
                        protocol = protocol,
                        location = location,
                        runtimeProfileUrl = subscriptionUrl,
                        runtimeConfig = runtimeConfig,
                    )
                }
            }

            ACTION_DISCONNECT -> {
                teardownTunnel()
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        teardownTunnel()
        super.onDestroy()
    }

    private fun establishTunnel(
        protocol: String,
        location: String,
        runtimeProfileUrl: String,
        runtimeConfig: String,
    ) {
        if (vpnInterface != null) {
            ArbuzVpnStateHolder.update(
                connected = true,
                protocol = protocol,
                location = location,
                details = "Tunnel already active",
            )
            return
        }

        val builder = Builder()
            .setSession("Arbuz VPN")
            .addAddress("10.10.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("1.1.1.1")

        val descriptor = builder.establish()
        if (descriptor == null) {
            ArbuzVpnStateHolder.update(
                connected = false,
                protocol = "N/A",
                location = "Not connected",
                details = "Failed to establish VPN interface",
            )
            return
        }

        vpnInterface = descriptor
        val coreStart = startNativeCore(runtimeProfileUrl, runtimeConfig)
        if (!coreStart.started) {
            teardownTunnel(reason = coreStart.details)
            return
        }
        ArbuzVpnStateHolder.update(
            connected = true,
            protocol = protocol,
            location = location,
            details = coreStart.details,
            processAlive = true,
        )
    }

    private fun teardownTunnel(reason: String = "Tunnel stopped") {
        monitorActive = false
        coreProcess?.destroy()
        coreProcess = null
        try {
            vpnInterface?.close()
        } catch (_: IOException) {
            // No-op: best effort close.
        } finally {
            vpnInterface = null
            ArbuzVpnStateHolder.update(
                connected = false,
                protocol = "N/A",
                location = "Not connected",
                details = reason,
                processAlive = false,
            )
        }
    }

    private fun startNativeCore(runtimeProfileUrl: String, runtimeConfig: String): CoreStartResult {
        if (runtimeProfileUrl.isBlank() && runtimeConfig.isBlank()) {
            return CoreStartResult(
                started = false,
                details = "Runtime profile payload is empty; tunnel has no outbound core.",
            )
        }
        val binary = resolveCoreBinary() ?: return CoreStartResult(
            started = false,
            details = "sing-box binary missing; tunnel has no outbound core.",
        )
        val configFile = File(filesDir, "singbox-runtime.json")
        return try {
            val configFetch = writeRuntimeConfig(
                profileUrl = runtimeProfileUrl,
                runtimeConfig = runtimeConfig,
                destination = configFile,
            )
            if (!configFetch.ok) {
                return CoreStartResult(started = false, details = configFetch.details)
            }
            val process = ProcessBuilder(
                binary.absolutePath,
                "run",
                "-D",
                filesDir.absolutePath,
                "-c",
                configFile.absolutePath,
            )
                .redirectErrorStream(true)
                .start()
            coreProcess = process
            consumeLogs(process)
            monitorProcessExit(process)
            startHealthMonitor(process)
            CoreStartResult(
                started = true,
                details = "Android VpnService tunnel active with sing-box core",
            )
        } catch (exc: Exception) {
            CoreStartResult(
                started = false,
                details = "Failed to start sing-box core: ${exc.message}",
            )
        }
    }

    private fun resolveCoreBinary(): File? {
        val local = File(filesDir, "sing-box")
        if (local.exists()) {
            local.setExecutable(true)
            return local
        }
        val fallback = File("/data/local/tmp/sing-box")
        if (fallback.exists()) {
            fallback.setExecutable(true)
            return fallback
        }
        return null
    }

    private fun writeRuntimeConfig(
        profileUrl: String,
        runtimeConfig: String,
        destination: File,
    ): ConfigFetchResult {
        val inlineConfig = runtimeConfig.trim()
        if (inlineConfig.isNotEmpty()) {
            return validateAndWriteRuntimeConfig(
                raw = inlineConfig,
                destination = destination,
                source = "inline runtime config",
            )
        }
        if (profileUrl.isBlank()) {
            return ConfigFetchResult(
                ok = false,
                details = "Runtime profile URL is empty",
            )
        }
        val connection = try {
            URL(profileUrl).openConnection() as HttpURLConnection
        } catch (exc: Exception) {
            return ConfigFetchResult(
                ok = false,
                details = "Invalid runtime profile URL: ${exc.message}",
            )
        }
        connection.connectTimeout = 8000
        connection.readTimeout = 10000
        connection.requestMethod = "GET"
        return try {
            val code = connection.responseCode
            if (code < 200 || code >= 300) {
                val errorBody = connection.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
                ConfigFetchResult(
                    ok = false,
                    details = "Runtime config request failed: HTTP $code ${errorBody.take(180)}".trim(),
                )
            } else {
                val raw = connection.inputStream.bufferedReader().use { it.readText() }.trim()
                if (raw.isEmpty()) {
                    ConfigFetchResult(
                        ok = false,
                        details = "Runtime config response is empty",
                    )
                } else {
                    validateAndWriteRuntimeConfig(
                        raw = raw,
                        destination = destination,
                        source = "downloaded runtime config",
                    )
                }
            }
        } catch (exc: Exception) {
            ConfigFetchResult(
                ok = false,
                details = "Runtime config fetch failed: ${exc.javaClass.simpleName}: ${exc.message}",
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun validateAndWriteRuntimeConfig(
        raw: String,
        destination: File,
        source: String,
    ): ConfigFetchResult {
        return runCatching { JSONObject(raw) }.fold(
            onSuccess = {
                destination.writeText(raw)
                ConfigFetchResult(
                    ok = true,
                    details = source.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() },
                )
            },
            onFailure = {
                val snippet = raw.take(180).replace("\n", " ")
                val hint = if (raw.contains("://")) {
                    "Looks like subscription links, not sing-box JSON."
                } else {
                    "Response is not a sing-box JSON object."
                }
                ConfigFetchResult(
                    ok = false,
                    details = "$hint Snippet: $snippet",
                )
            },
        )
    }

    private fun consumeLogs(process: Process) {
        thread(start = true, isDaemon = true, name = "arbuz-singbox-log") {
            runCatching {
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        println("[arbuz-singbox] $line")
                    }
                }
            }
        }
    }

    private fun monitorProcessExit(process: Process) {
        thread(start = true, isDaemon = true, name = "arbuz-singbox-watchdog") {
            runCatching {
                val code = process.waitFor()
                if (coreProcess === process) {
                    teardownTunnel(reason = "sing-box core exited with code $code")
                }
            }
        }
    }

    private fun startHealthMonitor(process: Process) {
        monitorActive = true
        thread(start = true, isDaemon = true, name = "arbuz-singbox-health") {
            while (monitorActive && coreProcess === process && vpnInterface != null) {
                if (!process.isAlive) {
                    teardownTunnel(reason = "sing-box core is not alive")
                    return@thread
                }
                ArbuzVpnStateHolder.heartbeat(
                    processAlive = true,
                    details = "VPN runtime healthy",
                )
                Thread.sleep(2000)
            }
        }
    }

    private fun extractLocation(subscriptionUrl: String): String {
        return runCatching {
            val uri = URI(subscriptionUrl)
            if (!uri.host.isNullOrBlank()) uri.host else "Auto route"
        }.getOrDefault("Auto route")
    }

    companion object {
        const val ACTION_CONNECT = "com.arbuzvpn.arbuz_vpn_app.ACTION_CONNECT"
        const val ACTION_DISCONNECT = "com.arbuzvpn.arbuz_vpn_app.ACTION_DISCONNECT"
        const val EXTRA_SUBSCRIPTION_URL = "subscription_url"
        const val EXTRA_RUNTIME_CONFIG = "runtime_config"
        const val EXTRA_PROTOCOL = "protocol"
    }

    private data class CoreStartResult(
        val started: Boolean,
        val details: String,
    )

    private data class ConfigFetchResult(
        val ok: Boolean,
        val details: String,
    )
}

object ArbuzVpnStateHolder {
    @Volatile
    private var connected: Boolean = false

    @Volatile
    private var protocol: String = "N/A"

    @Volatile
    private var location: String = "Not connected"

    @Volatile
    private var details: String = "Disconnected"

    @Volatile
    private var processAlive: Boolean = false

    @Volatile
    private var lastUpdateMs: Long = System.currentTimeMillis()

    fun update(
        connected: Boolean,
        protocol: String,
        location: String,
        details: String,
        processAlive: Boolean = false,
    ) {
        this.connected = connected
        this.protocol = protocol
        this.location = location
        this.details = details
        this.processAlive = processAlive
        this.lastUpdateMs = System.currentTimeMillis()
    }

    fun heartbeat(
        processAlive: Boolean,
        details: String? = null,
    ) {
        this.processAlive = processAlive
        if (!details.isNullOrBlank()) {
            this.details = details
        }
        this.lastUpdateMs = System.currentTimeMillis()
    }

    fun asMap(): Map<String, Any> {
        return mapOf(
            "connected" to connected,
            "protocol" to protocol,
            "location" to location,
            "details" to details,
            "processAlive" to processAlive,
            "lastUpdateMs" to lastUpdateMs,
        )
    }
}
