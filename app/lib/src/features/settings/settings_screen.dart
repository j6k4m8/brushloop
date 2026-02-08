import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../ui/studio_theme.dart';

/// Settings page for user-level profile and session actions.
class SettingsScreen extends StatefulWidget {
  /// Creates settings screen.
  const SettingsScreen({super.key, required this.controller});

  /// Shared app controller.
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _displayNameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.controller.session?.user.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _saveDisplayName() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty || _saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await widget.controller.updateDisplayName(displayName);
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name updated')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update display name: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _logout() {
    widget.controller.logout();
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.session;
    final email = session?.user.email ?? '';

    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                StudioPanel(
                  color: StudioPalette.chrome,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      StudioIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Settings',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StudioPanel(
                    child: ListView(
                      children: <Widget>[
                        const StudioSectionLabel('Profile'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Email: $email',
                          style: const TextStyle(
                            fontSize: 12,
                            color: StudioPalette.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        StudioButton(
                          label: _saving ? 'Saving...' : 'Save Display Name',
                          icon: Icons.save_outlined,
                          onPressed: _saving ? null : _saveDisplayName,
                        ),
                        const SizedBox(height: 22),
                        const StudioSectionLabel('Session'),
                        const SizedBox(height: 8),
                        StudioButton(
                          label: 'Sign Out',
                          icon: Icons.logout,
                          danger: true,
                          onPressed: _logout,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
