import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var vpnConnected: Bool = false
  private var vpnProtocol: String = "N/A"
  private var vpnLocation: String = "Not connected"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupVpnChannel(messenger: engineBridge.binaryMessenger)
  }

  private func setupVpnChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "arbuz.vpn/control", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(
          FlutterError(
            code: "state_unavailable",
            message: "App delegate state is unavailable",
            details: nil
          )
        )
        return
      }

      switch call.method {
      case "connect":
        let args = call.arguments as? [String: Any]
        let rawProtocol = (args?["protocol"] as? String) ?? "N/A"
        self.vpnProtocol = rawProtocol.uppercased()
        if
          let subscriptionUrl = args?["subscriptionUrl"] as? String,
          let host = URL(string: subscriptionUrl)?.host,
          !host.isEmpty
        {
          self.vpnLocation = host
        } else {
          self.vpnLocation = "Auto route"
        }
        self.vpnConnected = true
        result(self.buildState())

      case "disconnect":
        self.vpnConnected = false
        self.vpnProtocol = "N/A"
        self.vpnLocation = "Not connected"
        result(self.buildState())

      case "status":
        result(self.buildState())

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func buildState() -> [String: Any] {
    return [
      "connected": vpnConnected,
      "protocol": vpnProtocol,
      "location": vpnLocation,
      "details": vpnConnected ? "Platform channel runtime active" : "Disconnected",
    ]
  }
}
