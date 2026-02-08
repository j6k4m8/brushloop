import 'package:flutter/material.dart';

import '../../state/app_controller.dart';

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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'BrushLoop',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _registerMode
                            ? 'Create your account'
                            : 'Sign in to collaborate',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (_registerMode)
                        TextField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      if (_registerMode) const SizedBox(height: 12),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: controller.isBusy ? null : _submit,
                        child: Text(_registerMode ? 'Create Account' : 'Sign In'),
                      ),
                      TextButton(
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
                        ),
                      ),
                      if (controller.isBusy)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Center(child: CircularProgressIndicator()),
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
