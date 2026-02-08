import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../ui/studio_theme.dart';

/// Authentication screen supporting login and registration.
class AuthScreen extends StatefulWidget {
  /// Creates an auth screen.
  const AuthScreen({super.key, required this.controller});

  /// App controller used for auth actions.
  final AppController controller;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _registerMode = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      return;
    }

    try {
      if (_registerMode) {
        final displayName = _displayNameController.text.trim();
        if (displayName.isEmpty) {
          return;
        }
        await widget.controller.register(
          email: email,
          password: password,
          displayName: displayName,
        );
      } else {
        await widget.controller.login(email: email, password: password);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.controller.errorMessage ?? 'Authentication failed'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      body: StudioBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StudioPanel(
              padding: const EdgeInsets.all(20),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Text(
                        'BRUSHLOOP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _registerMode
                            ? 'Create your studio account'
                            : 'Sign in to your studio',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: StudioPalette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_registerMode)
                        TextField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                      if (_registerMode) const SizedBox(height: 10),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                      ),
                      const SizedBox(height: 14),
                      StudioButton(
                        label: _registerMode ? 'Create Account' : 'Sign In',
                        onPressed: controller.isBusy ? null : _submit,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : () {
                                  setState(() {
                                    _registerMode = !_registerMode;
                                  });
                                },
                          child: Text(
                            _registerMode
                                ? 'Already have an account? Sign in'
                                : 'Need an account? Register',
                            style: const TextStyle(color: StudioPalette.textMuted),
                          ),
                        ),
                      ),
                      if (controller.isBusy)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
