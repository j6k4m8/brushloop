import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../artwork/artwork_screen.dart';

/// Home screen listing contacts and active artworks.
class HomeScreen extends StatelessWidget {
  /// Creates a home screen.
  const HomeScreen({super.key, required this.controller});

  /// App controller used for data and actions.
  final AppController controller;

  Future<void> _openInviteDialog(BuildContext context) async {
    final emailController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Invite Contact'),
            content: TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  await controller.inviteContact(emailController.text.trim());
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Send Invite'),
              ),
            ],
          );
        },
      );
    } finally {
      emailController.dispose();
    }
  }

  Future<void> _openCreateArtworkDialog(BuildContext context) async {
    if (controller.contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one contact before creating artworks.'),
        ),
      );
      return;
    }

    ContactSummary selected = controller.contacts.first;
    ArtworkMode mode = ArtworkMode.realTime;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Artwork'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<ContactSummary>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Contact'),
                    items: controller.contacts
                        .map(
                          (contact) => DropdownMenuItem<ContactSummary>(
                            value: contact,
                            child: Text(contact.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selected = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ArtworkMode>(
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'Mode'),
                    items: const <DropdownMenuItem<ArtworkMode>>[
                      DropdownMenuItem(
                        value: ArtworkMode.realTime,
                        child: Text('Real-time'),
                      ),
                      DropdownMenuItem(
                        value: ArtworkMode.turnBased,
                        child: Text('Turn-based'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        mode = value;
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    await controller.createArtworkWithContact(
                      contact: selected,
                      mode: mode,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openArtwork(BuildContext context, ArtworkSummary artwork) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtworkScreen(
          controller: controller,
          artwork: artwork,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('BrushLoop'),
            actions: <Widget>[
              IconButton(
                onPressed: controller.isBusy ? null : controller.refreshHome,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
              IconButton(
                onPressed: controller.logout,
                icon: const Icon(Icons.logout),
                tooltip: 'Sign out',
              ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FloatingActionButton.extended(
                heroTag: 'invite-contact',
                onPressed: () => _openInviteDialog(context),
                icon: const Icon(Icons.person_add),
                label: const Text('Invite'),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'new-artwork',
                onPressed: () => _openCreateArtworkDialog(context),
                icon: const Icon(Icons.brush),
                label: const Text('New Artwork'),
              ),
            ],
          ),
          body: controller.isBusy
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final twoPane = constraints.maxWidth > 900;
                    final contactsPane = _ContactsPane(controller: controller);
                    final artworksPane = _ArtworksPane(
                      controller: controller,
                      onTapArtwork: (item) => _openArtwork(context, item),
                    );

                    if (twoPane) {
                      return Row(
                        children: <Widget>[
                          Expanded(flex: 4, child: contactsPane),
                          const VerticalDivider(width: 1),
                          Expanded(flex: 6, child: artworksPane),
                        ],
                      );
                    }

                    return ListView(
                      children: <Widget>[
                        SizedBox(height: 320, child: contactsPane),
                        const Divider(height: 1),
                        SizedBox(height: 420, child: artworksPane),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}

class _ContactsPane extends StatelessWidget {
  const _ContactsPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Contacts', style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: controller.contacts.isEmpty
              ? const Center(
                  child: Text('No contacts yet. Invite someone to collaborate.'),
                )
              : ListView.builder(
                  itemCount: controller.contacts.length,
                  itemBuilder: (context, index) {
                    final contact = controller.contacts[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(contact.displayName),
                      subtitle: Text(contact.email),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ArtworksPane extends StatelessWidget {
  const _ArtworksPane({
    required this.controller,
    required this.onTapArtwork,
  });

  final AppController controller;
  final ValueChanged<ArtworkSummary> onTapArtwork;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Active Artworks',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: controller.artworks.isEmpty
              ? const Center(child: Text('No artworks yet.'))
              : ListView.builder(
                  itemCount: controller.artworks.length,
                  itemBuilder: (context, index) {
                    final artwork = controller.artworks[index];
                    return ListTile(
                      leading: Icon(
                        artwork.mode == ArtworkMode.realTime
                            ? Icons.flash_on
                            : Icons.hourglass_bottom,
                      ),
                      title: Text(artwork.title),
                      subtitle: Text(
                        artwork.mode == ArtworkMode.realTime
                            ? 'Real-time collaboration'
                            : 'Turn-based collaboration',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => onTapArtwork(artwork),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
