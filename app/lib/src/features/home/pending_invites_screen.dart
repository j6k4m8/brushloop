import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../ui/studio_theme.dart';

/// Screen showing pending contact invitations with accept/decline actions.
class PendingInvitesScreen extends StatelessWidget {
  /// Creates the pending invites screen.
  const PendingInvitesScreen({super.key, required this.controller});

  /// App controller used to read invitation state and perform actions.
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final invites = controller.pendingInvitations;

        return Scaffold(
          body: StudioBackdrop(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    StudioPanel(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      color: StudioPalette.chrome,
                      child: Row(
                        children: <Widget>[
                          StudioIconButton(
                            icon: Icons.arrow_back,
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Pending Invites',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          StudioIconButton(
                            icon: Icons.refresh,
                            tooltip: 'Refresh',
                            onPressed: controller.isBusy ? null : controller.refreshHome,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: StudioPanel(
                        child: controller.isBusy && invites.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : invites.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No pending invites.',
                                      style: TextStyle(color: StudioPalette.textMuted),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: invites.length,
                                    separatorBuilder: (context, index) => const Divider(height: 12),
                                    itemBuilder: (context, index) {
                                      final invite = invites[index];
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: StudioPalette.panelSoft,
                                          border: Border.all(color: StudioPalette.border),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        child: Row(
                                          children: <Widget>[
                                            const Icon(Icons.mail_outline, size: 18),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: <Widget>[
                                                  Text(
                                                    invite.inviterDisplayName,
                                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    invite.inviterEmail ?? invite.inviterUserId,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: StudioPalette.textMuted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            StudioButton(
                                              label: 'Deny',
                                              danger: true,
                                              onPressed: controller.isBusy
                                                  ? null
                                                  : () async {
                                                      try {
                                                        await controller.declineInvitation(invite.id);
                                                      } catch (error) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(content: Text('$error')),
                                                          );
                                                        }
                                                      }
                                                    },
                                            ),
                                            const SizedBox(width: 6),
                                            StudioButton(
                                              label: 'Accept',
                                              onPressed: controller.isBusy
                                                  ? null
                                                  : () async {
                                                      try {
                                                        await controller.acceptInvitation(invite.id);
                                                      } catch (error) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(content: Text('$error')),
                                                          );
                                                        }
                                                      }
                                                    },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
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
