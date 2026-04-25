package com.arbuzvpn.arbuz_vpn_app

import android.content.Intent
import android.net.VpnService
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val vpnPermissionRequestCode = 4901

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "arbuz.vpn/control")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installCoreFromTmp" -> {
                        result.success(installCoreFromTmp())
                    }
                    "coreStatus" -> {
                        result.success(coreStatus())
                    }
                    "connect" -> {
                        val args = call.arguments as? Map<*, *>
                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            startActivityForResult(prepareIntent, vpnPermissionRequestCode)
                            result.error(
                                "permission_required",
                                "Allow VPN permission in Android dialog and tap connect again.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        val protocol = (args?.get("protocol") as? String)?.uppercase() ?: "N/A"
                        val subscriptionUrl = args?.get("subscriptionUrl") as? String
                        val runtimeConfig = args?.get("runtimeConfig") as? String
                        val location = runCatching {
                            val uri = java.net.URI(subscriptionUrl ?: "")
                            if (!uri.host.isNullOrBlank()) uri.host else "Auto route"
                        }.getOrDefault("Auto route")
                        val serviceIntent = Intent(this, ArbuzVpnService::class.java).apply {
                            action = ArbuzVpnService.ACTION_CONNECT
                            putExtra(ArbuzVpnService.EXTRA_PROTOCOL, protocol)
                            putExtra(ArbuzVpnService.EXTRA_SUBSCRIPTION_URL, subscriptionUrl ?: "")
                            putExtra(ArbuzVpnService.EXTRA_RUNTIME_CONFIG, runtimeConfig ?: "")
                        }
                        startService(serviceIntent)
                        result.success(
                            mapOf(
                                "connected" to false,
                                "protocol" to protocol,
                                "location" to location,
                                "details" to "Connecting VPN runtime...",
                            )
                        )
                    }
                    "disconnect" -> {
                        val serviceIntent = Intent(this, ArbuzVpnService::class.java).apply {
                            action = ArbuzVpnService.ACTION_DISCONNECT
                        }
                        startService(serviceIntent)
                        result.success(
                            mapOf(
                                "connected" to false,
                                "protocol" to "N/A",
                                "location" to "Not connected",
                                "details" to "Disconnected",
                            )
                        )
                    }
                    "status" -> {
                        result.success(ArbuzVpnStateHolder.asMap())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installCoreFromTmp(): Map<String, Any> {
        val target = File(filesDir, "sing-box")
        if (target.exists()) {
            target.setExecutable(true)
            return mapOf(
                "installed" to true,
                "path" to target.absolutePath,
                "source" to "files",
                "details" to "Core binary already installed",
            )
        }
        val source = File("/data/local/tmp/sing-box")
        if (!source.exists()) {
            return mapOf(
                "installed" to false,
                "path" to target.absolutePath,
                "source" to "none",
                "details" to "No source binary at /data/local/tmp/sing-box",
            )
        }
        return try {
            source.inputStream().use { input ->
                target.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            target.setExecutable(true)
            mapOf(
                "installed" to true,
                "path" to target.absolutePath,
                "source" to source.absolutePath,
                "details" to "Core binary copied to app files",
            )
        } catch (exc: Exception) {
            mapOf(
                "installed" to false,
                "path" to target.absolutePath,
                "source" to source.absolutePath,
                "details" to "Failed to copy core binary: ${exc.message}",
            )
        }
    }

    private fun coreStatus(): Map<String, Any> {
        val local = File(filesDir, "sing-box")
        val tmp = File("/data/local/tmp/sing-box")
        val runtime = ArbuzVpnStateHolder.asMap()
        return mapOf(
            "localExists" to local.exists(),
            "localPath" to local.absolutePath,
            "tmpExists" to tmp.exists(),
            "tmpPath" to tmp.absolutePath,
            "runtimeConnected" to (runtime["connected"] == true),
            "runtimeProcessAlive" to (runtime["processAlive"] == true),
            "runtimeDetails" to (runtime["details"] ?: ""),
            "runtimeLastUpdateMs" to (runtime["lastUpdateMs"] ?: 0L),
        )
    }
}
