import 'dart:async';

import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'network/api_client.dart';
import 'state/app_controller.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';
import 'ui/studio_theme.dart';

/// Root widget for the BrushLoop Flutter client.
class BrushLoopApp extends StatefulWidget {
  /// Creates the application root.
  const BrushLoopApp({super.key});

  @override
  State<BrushLoopApp> createState() => _BrushLoopAppState();
}

class _BrushLoopAppState extends State<BrushLoopApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    final apiClient = ApiClient(baseUrl: AppConfig.apiBaseUrl);
    _controller = AppController(apiClient: apiClient);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BrushLoop',
      theme: buildStudioTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.isRestoringSession) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (_controller.session == null) {
            return AuthScreen(controller: _controller);
          }

          return HomeScreen(controller: _controller);
        },
      ),
    );
  }
}
