import 'package:flutter/material.dart';

import '../../state/app_controller.dart';

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
          appBar: AppBar(
            title: const Text('Pending Invites'),
            actions: <Widget>[
              IconButton(
                onPressed: controller.isBusy ? null : controller.refreshHome,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: controller.isBusy && invites.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : invites.isEmpty
                  ? const Center(child: Text('No pending invites.'))
                  : ListView.separated(
                      itemCount: invites.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final invite = invites[index];
                        return ListTile(
                          leading: const Icon(Icons.mark_email_unread_outlined),
                          title: Text(invite.inviterDisplayName),
                          subtitle: Text(invite.inviterEmail ?? invite.inviterUserId),
                          trailing: Wrap(
                            spacing: 8,
                            children: <Widget>[
                              TextButton(
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
                                child: const Text('Deny'),
                              ),
                              FilledButton(
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
                                child: const Text('Accept'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        );
      },
    );
  }
}
