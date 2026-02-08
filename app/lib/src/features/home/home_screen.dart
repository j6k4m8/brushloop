import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../../ui/studio_theme.dart';
import '../artwork/artwork_screen.dart';
import '../chat/chat_screen.dart';
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
          return Dialog(
            child: StudioPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Invite Contact',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      StudioButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      StudioButton(
                        label: 'Send Invite',
                        onPressed: () async {
                          await controller.inviteContact(emailController.text.trim());
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

  Future<void> _openChat(BuildContext context, ContactSummary contact) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          controller: controller,
          contact: contact,
        ),
      ),
    );

    if (context.mounted) {
      await controller.refreshHome();
    }
  }

  Future<void> _openRenameArtworkDialog(
    BuildContext context,
    ArtworkSummary artwork,
  ) async {
    final titleController = TextEditingController(text: artwork.title);
    var shouldSave = false;
    var pendingTitle = artwork.title;

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return Dialog(
            child: StudioPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Rename Artwork',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      StudioButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: 8),
                      StudioButton(
                        label: 'Save',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      shouldSave = result == true;
      pendingTitle = titleController.text.trim();
    } finally {
      titleController.dispose();
    }

    if (!shouldSave || !context.mounted) {
      return;
    }

    final title = pendingTitle;
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title cannot be empty')),
      );
      return;
    }

    try {
      await controller.renameArtworkTitle(
        artworkId: artwork.id,
        title: title,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rename artwork: $error')),
      );
    }
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
          body: StudioBackdrop(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: <Widget>[
                    StudioPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      color: StudioPalette.chrome,
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.palette_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'BrushLoop Studio',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          StudioIconButton(
                            icon: Icons.refresh,
                            tooltip: 'Refresh',
                            onPressed: controller.isBusy ? null : controller.refreshHome,
                          ),
                          const SizedBox(width: 6),
                          StudioButton(
                            label: 'Invite',
                            icon: Icons.person_add_alt_1,
                            onPressed: () => _openInviteDialog(context),
                          ),
                          const SizedBox(width: 6),
                          StudioButton(
                            label: 'New Artwork',
                            icon: Icons.add_photo_alternate_outlined,
                            onPressed: () => _openCreateArtworkDialog(context),
                          ),
                          const SizedBox(width: 6),
                          StudioIconButton(
                            icon: Icons.logout,
                            tooltip: 'Sign out',
                            onPressed: controller.logout,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: controller.isBusy
                          ? const Center(child: CircularProgressIndicator())
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final twoPane = constraints.maxWidth > 900;
                                final contactsPane = _ContactsPane(
                                  controller: controller,
                                  onOpenPendingInvites: () => _openPendingInvites(context),
                                  onTapContact: (contact) => _openChat(context, contact),
                                );
                                final artworksPane = _ArtworksPane(
                                  controller: controller,
                                  onTapArtwork: (item) => _openArtwork(context, item),
                                  onRenameArtwork: (item) => _openRenameArtworkDialog(context, item),
                                );

                                if (twoPane) {
                                  return Row(
                                    children: <Widget>[
                                      SizedBox(width: 340, child: contactsPane),
                                      const SizedBox(width: 10),
                                      Expanded(child: artworksPane),
                                    ],
                                  );
                                }

                                return Column(
                                  children: <Widget>[
                                    Expanded(flex: 4, child: contactsPane),
                                    const SizedBox(height: 10),
                                    Expanded(flex: 5, child: artworksPane),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
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
  _InitialTurnChoice _firstTurnChoice = _InitialTurnChoice.me;
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
      final sessionUser = widget.controller.session?.user;
      final firstTurnUserId = _mode != ArtworkMode.turnBased
          ? null
          : (_soloArtwork ||
                  _selectedContact == null ||
                  _firstTurnChoice == _InitialTurnChoice.me)
              ? sessionUser?.id
              : _selectedContact!.userId;

      await widget.controller.createArtwork(
        mode: _mode,
        collaborator: _soloArtwork ? null : _selectedContact,
        firstTurnUserId: firstTurnUserId,
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
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: StudioPanel(
          padding: const EdgeInsets.all(14),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Create Artwork',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (widget.controller.contacts.isNotEmpty)
                  CheckboxListTile(
                    value: _soloArtwork,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Solo Artwork'),
                    subtitle: const Text(
                      'Create this artwork just for yourself',
                      style: TextStyle(fontSize: 12, color: StudioPalette.textMuted),
                    ),
                    onChanged: _isSubmitting
                        ? null
                        : (value) {
                            setState(() {
                              _soloArtwork = value ?? false;
                              if (!_soloArtwork &&
                                  _selectedContact == null &&
                                  widget.controller.contacts.isNotEmpty) {
                                _selectedContact = widget.controller.contacts.first;
                              }
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
                  const SizedBox(height: 10),
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
                if (_mode == ArtworkMode.turnBased) ...<Widget>[
                  const SizedBox(height: 10),
                  _soloArtwork || _selectedContact == null
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First turn: You',
                            style: TextStyle(
                              fontSize: 12,
                              color: StudioPalette.textMuted,
                            ),
                          ),
                        )
                      : DropdownButtonFormField<_InitialTurnChoice>(
                          initialValue: _firstTurnChoice,
                          decoration: const InputDecoration(labelText: 'First turn'),
                          items: <DropdownMenuItem<_InitialTurnChoice>>[
                            const DropdownMenuItem<_InitialTurnChoice>(
                              value: _InitialTurnChoice.me,
                              child: Text('You'),
                            ),
                            DropdownMenuItem<_InitialTurnChoice>(
                              value: _InitialTurnChoice.contact,
                              child: Text(_selectedContact!.displayName),
                            ),
                          ],
                          onChanged: _isSubmitting
                              ? null
                              : (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() {
                                    _firstTurnChoice = value;
                                  });
                                },
                        ),
                ],
                const SizedBox(height: 14),
                const StudioSectionLabel('Base Photo'),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StudioButton(
                        label: 'Camera',
                        icon: Icons.photo_camera_outlined,
                        onPressed: _isSubmitting || _isPickingPhoto
                            ? null
                            : () => _pickPhoto(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StudioButton(
                        label: 'Gallery',
                        icon: Icons.photo_library_outlined,
                        onPressed: _isSubmitting || _isPickingPhoto
                            ? null
                            : () => _pickPhoto(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                if (_isPickingPhoto)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_photo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: StudioPalette.panelSoft,
                        border: Border.all(color: StudioPalette.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.memory(
                              _photo!.bytes,
                              width: 84,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _photo!.filename,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          StudioIconButton(
                            icon: Icons.close,
                            tooltip: 'Remove',
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    setState(() {
                                      _photo = null;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    StudioButton(
                      label: 'Cancel',
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    StudioButton(
                      label: _isSubmitting ? 'Creating...' : 'Create',
                      onPressed: _isSubmitting ? null : _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _InitialTurnChoice {
  me,
  contact,
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
    required this.onTapContact,
  });

  final AppController controller;
  final VoidCallback onOpenPendingInvites;
  final ValueChanged<ContactSummary> onTapContact;

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: StudioSectionLabel('Contacts')),
              StudioButton(
                label: 'Pending (${controller.pendingInvitations.length})',
                icon: Icons.mark_email_unread_outlined,
                onPressed: onOpenPendingInvites,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: controller.contacts.isEmpty
                ? const Center(
                    child: Text(
                      'No contacts yet. Invite someone to collaborate.',
                      style: TextStyle(color: StudioPalette.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: controller.contacts.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final contact = controller.contacts[index];
                      return Material(
                        color: StudioPalette.panelSoft,
                        borderRadius: BorderRadius.circular(4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => onTapContact(contact),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: StudioPalette.border),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: <Widget>[
                                const Icon(Icons.person_outline, size: 17),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        contact.displayName,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        contact.email,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: StudioPalette.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (contact.unreadMessageCount > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: StudioPalette.accent,
                                      ),
                                    ),
                                  ),
                                const Icon(Icons.chat_bubble_outline, size: 15),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ArtworksPane extends StatelessWidget {
  const _ArtworksPane({
    required this.controller,
    required this.onTapArtwork,
    required this.onRenameArtwork,
  });

  final AppController controller;
  final ValueChanged<ArtworkSummary> onTapArtwork;
  final ValueChanged<ArtworkSummary> onRenameArtwork;

  /// Resolves a participant id into display name when available.
  String _displayNameForUserId(String userId) {
    for (final contact in controller.contacts) {
      if (contact.userId == userId) {
        return contact.displayName;
      }
    }

    if (userId.length <= 16) {
      return userId;
    }
    return '${userId.substring(0, 16)}...';
  }

  /// Formats a collaboration descriptor for home list rows.
  String _artworkDescriptor(ArtworkSummary artwork) {
    final sessionUserId = controller.session?.user.id;
    final collaboratorIds = artwork.participantUserIds
        .where((userId) => userId != sessionUserId)
        .toList();

    if (collaboratorIds.isEmpty) {
      return 'Private artwork';
    }

    final collaboratorNames =
        collaboratorIds.map(_displayNameForUserId).toList();

    final modeLabel =
        artwork.mode == ArtworkMode.realTime ? 'Real-time' : 'Turn-based';
    if (collaboratorNames.length == 1) {
      return '$modeLabel with ${collaboratorNames.first}';
    }

    return '$modeLabel with ${collaboratorNames.first} +${collaboratorNames.length - 1}';
  }

  @override
  Widget build(BuildContext context) {
    final sessionUserId = controller.session?.user.id;
    final orderedArtworks = controller.artworks.toList()
      ..sort((left, right) {
        final leftMyTurn = left.activeParticipantUserId == sessionUserId;
        final rightMyTurn = right.activeParticipantUserId == sessionUserId;
        if (leftMyTurn == rightMyTurn) {
          return 0;
        }
        return leftMyTurn ? -1 : 1;
      });

    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const StudioSectionLabel('Active Artworks'),
          const SizedBox(height: 10),
          Expanded(
            child: orderedArtworks.isEmpty
                ? const Center(
                    child: Text(
                      'No artworks yet.',
                      style: TextStyle(color: StudioPalette.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: orderedArtworks.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final artwork = orderedArtworks[index];
                      final isMyTurn = artwork.activeParticipantUserId == sessionUserId;
                      return Material(
                        color: StudioPalette.panelSoft,
                        borderRadius: BorderRadius.circular(4),
                        child: InkWell(
                          onTap: () => onTapArtwork(artwork),
                          onLongPress: () => onRenameArtwork(artwork),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: StudioPalette.border),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isMyTurn
                                        ? StudioPalette.accent
                                        : Colors.transparent,
                                    border: Border.all(
                                      color: isMyTurn
                                          ? StudioPalette.accent
                                          : StudioPalette.textMuted,
                                      width: isMyTurn ? 0 : 1.1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  artwork.mode == ArtworkMode.realTime
                                      ? Icons.bolt
                                      : Icons.schedule,
                                  size: 17,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        artwork.title,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _artworkDescriptor(artwork),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: StudioPalette.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
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
