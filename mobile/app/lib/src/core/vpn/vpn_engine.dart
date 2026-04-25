class VpnRuntimeState {
  const VpnRuntimeState({
    required this.connected,
    required this.protocol,
    required this.location,
    this.details,
  });

  const VpnRuntimeState.disconnected({
    this.protocol = 'N/A',
    this.location = 'Not connected',
    this.details,
  }) : connected = false;

  final bool connected;
  final String protocol;
  final String location;
  final String? details;
}

class VpnCoreStatus {
  const VpnCoreStatus({
    required this.available,
    this.path,
    this.details,
    this.runtimeConnected = false,
    this.runtimeProcessAlive = false,
    this.runtimeLastUpdateMs,
  });

  const VpnCoreStatus.unavailable({
    this.details = 'Core status is unavailable',
  })  : available = false,
        path = null,
        runtimeConnected = false,
        runtimeProcessAlive = false,
        runtimeLastUpdateMs = null;

  final bool available;
  final String? path;
  final String? details;
  final bool runtimeConnected;
  final bool runtimeProcessAlive;
  final int? runtimeLastUpdateMs;
}

abstract class VpnEngine {
  Future<VpnRuntimeState> connect({
    required String subscriptionUrl,
    String? runtimeConfig,
    required String protocol,
    required String username,
  });

  Future<VpnRuntimeState> disconnect();
  Future<VpnRuntimeState> currentState();

  Future<VpnCoreStatus> coreStatus() async {
    return const VpnCoreStatus.unavailable();
  }
}

class StubVpnEngine implements VpnEngine {
  VpnRuntimeState _state = const VpnRuntimeState.disconnected();

  @override
  Future<VpnRuntimeState> connect({
    required String subscriptionUrl,
    String? runtimeConfig,
    required String protocol,
    required String username,
  }) async {
    final uri = Uri.tryParse(subscriptionUrl);
    final location = uri?.host.isNotEmpty == true ? uri!.host : 'Auto route';
    _state = VpnRuntimeState(
      connected: true,
      protocol: protocol.toUpperCase(),
      location: location,
      details: 'Connected for $username via $location',
    );
    return _state;
  }

  @override
  Future<VpnRuntimeState> disconnect() async {
    _state = const VpnRuntimeState.disconnected();
    return _state;
  }

  @override
  Future<VpnRuntimeState> currentState() async {
    return _state;
  }

  @override
  Future<VpnCoreStatus> coreStatus() async {
    return const VpnCoreStatus(
      available: true,
      path: 'stub://in-memory',
      details: 'Stub VPN engine runtime',
    );
  }
}
