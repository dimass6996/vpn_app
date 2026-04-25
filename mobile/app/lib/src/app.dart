import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/config/app_config.dart';
import 'features/app_shell/app_controller.dart';
import 'features/app_shell/app_shell.dart';
import 'shared/app_theme.dart';

class ArbuzVpnApp extends StatefulWidget {
  const ArbuzVpnApp({
    super.key,
    this.controller,
  });

  final AppController? controller;

  @override
  State<ArbuzVpnApp> createState() => _ArbuzVpnAppState();
}

class _ArbuzVpnAppState extends State<ArbuzVpnApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? AppController(config: const AppConfig());
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _controller.initialize();
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arbuz VPN',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AppShell(controller: _controller),
    );
  }
}
