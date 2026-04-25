import 'package:flutter/services.dart';

import 'vpn_engine.dart';

class PlatformChannelVpnEngine implements VpnEngine {
  static const MethodChannel _channel = MethodChannel('arbuz.vpn/control');

  @override
  Future<VpnRuntimeState> connect({
    required String subscriptionUrl,
    required String protocol,
    required String username,
  }) async {
    await _attemptCoreInstallFromTmp();
    try {
      final payload = await _channel.invokeMapMethod<String, dynamic>(
        'connect',
        <String, dynamic>{
          'subscriptionUrl': subscriptionUrl,
          'protocol': protocol,
          'username': username,
        },
      );
      return _stateFromPayload(payload);
    } on PlatformException catch (error) {
      if (error.code == 'permission_required') {
        return const VpnRuntimeState.disconnected(
          details: 'Allow VPN permission and tap connect again.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<VpnRuntimeState> currentState() async {
    final payload = await _channel.invokeMapMethod<String, dynamic>('status');
    return _stateFromPayload(payload);
  }

  @override
  Future<VpnRuntimeState> disconnect() async {
    final payload = await _channel.invokeMapMethod<String, dynamic>('disconnect');
    return _stateFromPayload(payload);
  }

  VpnRuntimeState _stateFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) {
      return const VpnRuntimeState.disconnected();
    }
    final connected = payload['connected'] == true;
    final protocol = (payload['protocol'] as String?) ?? 'N/A';
    final location = (payload['location'] as String?) ?? 'Not connected';
    final details = payload['details'] as String?;
    if (!connected) {
      return VpnRuntimeState.disconnected(
        protocol: protocol,
        location: location,
        details: details,
      );
    }
    return VpnRuntimeState(
      connected: true,
      protocol: protocol,
      location: location,
      details: details,
    );
  }

  Future<void> _attemptCoreInstallFromTmp() async {
    try {
      await _channel.invokeMethod('installCoreFromTmp');
    } on MissingPluginException {
      // Non-Android platforms or channel unavailable.
    } on PlatformException {
      // Best effort, service will still attempt fallback.
    }
  }

  @override
  Future<VpnCoreStatus> coreStatus() async {
    try {
      final payload = await _channel.invokeMapMethod<String, dynamic>('coreStatus');
      if (payload == null) {
        return const VpnCoreStatus.unavailable(details: 'No core status payload');
      }
      final localExists = payload['localExists'] == true;
      final localPath = payload['localPath'] as String?;
      final tmpExists = payload['tmpExists'] == true;
      final tmpPath = payload['tmpPath'] as String?;
      final runtimeConnected = payload['runtimeConnected'] == true;
      final runtimeProcessAlive = payload['runtimeProcessAlive'] == true;
      final runtimeDetails = payload['runtimeDetails'] as String?;
      final runtimeLastUpdateMs = payload['runtimeLastUpdateMs'] as int?;
      if (localExists) {
        return VpnCoreStatus(
          available: true,
          path: localPath,
          details: runtimeDetails?.isNotEmpty == true
              ? runtimeDetails
              : 'Core is installed in app storage',
          runtimeConnected: runtimeConnected,
          runtimeProcessAlive: runtimeProcessAlive,
          runtimeLastUpdateMs: runtimeLastUpdateMs,
        );
      }
      if (tmpExists) {
        return VpnCoreStatus(
          available: true,
          path: tmpPath,
          details: 'Core available in /data/local/tmp (will auto-install on connect)',
          runtimeConnected: runtimeConnected,
          runtimeProcessAlive: runtimeProcessAlive,
          runtimeLastUpdateMs: runtimeLastUpdateMs,
        );
      }
      return VpnCoreStatus.unavailable(
        details: runtimeDetails?.isNotEmpty == true
            ? runtimeDetails
            : 'Core binary is missing on device',
      );
    } on MissingPluginException {
      return const VpnCoreStatus.unavailable(details: 'Platform channel unavailable');
    } on PlatformException catch (error) {
      return VpnCoreStatus.unavailable(details: error.message ?? error.code);
    }
  }
}

class ResilientVpnEngine implements VpnEngine {
  ResilientVpnEngine({
    VpnEngine? primary,
    VpnEngine? fallback,
  })  : _primary = primary ?? PlatformChannelVpnEngine(),
        _fallback = fallback ?? StubVpnEngine();

  final VpnEngine _primary;
  final VpnEngine _fallback;

  @override
  Future<VpnRuntimeState> connect({
    required String subscriptionUrl,
    required String protocol,
    required String username,
  }) async {
    try {
      return await _primary.connect(
        subscriptionUrl: subscriptionUrl,
        protocol: protocol,
        username: username,
      );
    } on MissingPluginException {
      return _fallback.connect(
        subscriptionUrl: subscriptionUrl,
        protocol: protocol,
        username: username,
      );
    }
  }

  @override
  Future<VpnRuntimeState> currentState() async {
    try {
      return await _primary.currentState();
    } on MissingPluginException {
      return _fallback.currentState();
    }
  }

  @override
  Future<VpnRuntimeState> disconnect() async {
    try {
      return await _primary.disconnect();
    } on MissingPluginException {
      return _fallback.disconnect();
    }
  }

  @override
  Future<VpnCoreStatus> coreStatus() async {
    try {
      return await _primary.coreStatus();
    } on MissingPluginException {
      return _fallback.coreStatus();
    }
  }
}
