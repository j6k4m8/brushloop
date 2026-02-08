import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../artwork/artwork_screen.dart';
import 'pending_invites_screen.dart';

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
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateArtworkDialog(controller: controller),
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

  Future<void> _openPendingInvites(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PendingInvitesScreen(controller: controller),
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
                    final contactsPane = _ContactsPane(
                      controller: controller,
                      onOpenPendingInvites: () => _openPendingInvites(context),
                    );
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

class _CreateArtworkDialog extends StatefulWidget {
  const _CreateArtworkDialog({required this.controller});

  final AppController controller;

  @override
  State<_CreateArtworkDialog> createState() => _CreateArtworkDialogState();
}

class _CreateArtworkDialogState extends State<_CreateArtworkDialog> {
  final ImagePicker _picker = ImagePicker();

  ContactSummary? _selectedContact;
  bool _soloArtwork = false;
  ArtworkMode _mode = ArtworkMode.realTime;
  _PickedArtworkPhoto? _photo;
  bool _isPickingPhoto = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller.contacts.isEmpty) {
      _soloArtwork = true;
      return;
    }

    _selectedContact = widget.controller.contacts.first;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    setState(() {
      _isPickingPhoto = true;
    });

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 3000,
        imageQuality: 95,
      );

      if (picked == null) {
        return;
      }

      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }

      setState(() {
        _photo = _PickedArtworkPhoto(
          bytes: bytes,
          filename: picked.name.isEmpty ? 'photo.jpg' : picked.name,
          mimeType: inferImageMimeType(picked.name),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo selection failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingPhoto = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      final basePhoto = _photo;
      await widget.controller.createArtwork(
        mode: _mode,
        collaborator: _soloArtwork ? null : _selectedContact,
        basePhoto: basePhoto == null
            ? null
            : ArtworkBasePhotoInput(
                bytes: basePhoto.bytes,
                filename: basePhoto.filename,
                mimeType: basePhoto.mimeType,
              ),
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create artwork: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Artwork'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.controller.contacts.isNotEmpty)
              SwitchListTile.adaptive(
                value: _soloArtwork,
                contentPadding: EdgeInsets.zero,
                title: const Text('Solo Artwork'),
                subtitle: const Text('Create this artwork just for yourself'),
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        setState(() {
                          _soloArtwork = value;
                        });
                      },
              ),
            if (!_soloArtwork && widget.controller.contacts.isNotEmpty) ...<Widget>[
              DropdownButtonFormField<ContactSummary>(
                initialValue: _selectedContact,
                decoration: const InputDecoration(labelText: 'Contact'),
                items: widget.controller.contacts
                    .map(
                      (contact) => DropdownMenuItem<ContactSummary>(
                        value: contact,
                        child: Text(contact.displayName),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _selectedContact = value;
                        });
                      },
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<ArtworkMode>(
              initialValue: _mode,
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
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _mode = value;
                      });
                    },
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Base Photo (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting || _isPickingPhoto
                        ? null
                        : () => _pickPhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSubmitting || _isPickingPhoto
                        ? null
                        : () => _pickPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_isPickingPhoto)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_photo != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _photo!.bytes,
                        width: 240,
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _photo!.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () {
                              setState(() {
                                _photo = null;
                              });
                            },
                      child: const Text('Remove Photo'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}

class _PickedArtworkPhoto {
  const _PickedArtworkPhoto({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

class _ContactsPane extends StatelessWidget {
  const _ContactsPane({
    required this.controller,
    required this.onOpenPendingInvites,
  });

  final AppController controller;
  final VoidCallback onOpenPendingInvites;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Contacts',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: onOpenPendingInvites,
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: Text(
                  'Pending Invites (${controller.pendingInvitations.length})',
                ),
              ),
            ],
          ),
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

String inferImageMimeType(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.heic')) {
    return 'image/heic';
  }

  return 'image/jpeg';
}
