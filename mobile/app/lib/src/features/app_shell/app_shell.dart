import 'package:flutter/material.dart';

import '../../shared/atmospheric_background.dart';
import '../../shared/app_theme.dart';
import '../auth/auth_screen.dart';
import '../home/home_screen.dart';
import '../settings/settings_screen.dart';
import 'app_controller.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.authStage == AuthStage.bootstrapping) {
          return const _BootstrapScreen();
        }

        if (controller.authStage != AuthStage.authenticated) {
          return AuthScreen(controller: controller);
        }

        final pages = [
          HomeScreen(controller: controller),
          SettingsScreen(controller: controller),
        ];

        return Scaffold(
          extendBody: true,
          appBar: AppBar(
            title: const Text('Arbuz VPN'),
            actions: [
              IconButton(
                onPressed: controller.isLoading ? null : controller.refreshDashboard,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
          body: AtmosphericBackground(
            child: SafeArea(
              top: false,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.995, end: 1).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(controller.selectedTab),
                  child: pages[controller.selectedTab],
                ),
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: controller.selectedTab,
            onDestinationSelected: controller.selectTab,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}

class _BootstrapScreen extends StatelessWidget {
  const _BootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AtmosphericBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(),
              ),
              SizedBox(height: 20),
              Text(
                'Restoring session',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
