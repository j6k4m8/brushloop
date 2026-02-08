import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../../ui/studio_theme.dart';
import '../artwork/artwork_screen.dart';

/// Direct chat workspace with one contact and shared artwork context.
class ChatScreen extends StatefulWidget {
  /// Creates a direct chat screen.
  const ChatScreen({
    super.key,
    required this.controller,
    required this.contact,
  });

  /// Shared app controller.
  final AppController controller;

  /// Contact currently selected from the home screen.
  final ContactSummary contact;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _timelineScrollController = ScrollController();

  ChatThread? _thread;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  bool _showMobileArtworkPane = false;

  @override
  void initState() {
    super.initState();
    _loadThread();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _timelineScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadThread() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final thread = await widget.controller.loadChatThread(widget.contact.userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _thread = thread;
      });
      _scrollTimelineToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _sending) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      final sent = await widget.controller.sendChatMessage(
        contactUserId: widget.contact.userId,
        body: body,
      );
      if (!mounted) {
        return;
      }

      _messageController.clear();
      final thread = _thread;
      if (thread != null) {
        setState(() {
          _thread = ChatThread(
            contact: thread.contact,
            artworks: thread.artworks,
            timeline: <ChatTimelineItem>[
              ...thread.timeline,
              ChatTimelineItem(
                id: 'message:${sent.id}',
                kind: ChatTimelineKind.message,
                createdAt: sent.createdAt,
                senderUserId: sent.senderUserId,
                recipientUserId: sent.recipientUserId,
                body: sent.body,
              ),
            ],
          );
        });
      } else {
        await _loadThread();
      }
      _scrollTimelineToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _scrollTimelineToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timelineScrollController.hasClients) {
        return;
      }
      _timelineScrollController.animateTo(
        _timelineScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openArtwork(String artworkId, {String? fallbackTitle}) async {
    ArtworkSummary? summary;
    final thread = _thread;
    if (thread != null) {
      for (final artwork in thread.artworks) {
        if (artwork.id == artworkId) {
          summary = artwork;
          break;
        }
      }
    }

    if (summary == null) {
      final details = await widget.controller.loadArtworkDetails(artworkId);
      summary = ArtworkSummary(
        id: details.artwork.id,
        title: fallbackTitle ?? details.artwork.title,
        mode: details.artwork.mode,
        participantUserIds:
            details.participants.map((participant) => participant.userId).toList(),
        activeParticipantUserId: details.currentTurn?.activeParticipantUserId,
      );
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtworkScreen(
          controller: widget.controller,
          artwork: summary!,
        ),
      ),
    );
  }

  String _displayNameForUserId(String userId) {
    final sessionUser = widget.controller.session?.user;
    if (sessionUser != null && sessionUser.id == userId) {
      return sessionUser.displayName;
    }

    for (final contact in widget.controller.contacts) {
      if (contact.userId == userId) {
        return contact.displayName;
      }
    }

    if (userId.length <= 16) {
      return userId;
    }
    return '${userId.substring(0, 16)}...';
  }

  Widget _buildTimeline(ChatThread thread) {
    final sessionUserId = widget.controller.session?.user.id;

    return ListView.builder(
      controller: _timelineScrollController,
      itemCount: thread.timeline.length,
      itemBuilder: (context, index) {
        final item = thread.timeline[index];
        if (item.kind == ChatTimelineKind.message) {
          final mine = item.senderUserId == sessionUserId;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: mine ? StudioPalette.accent : StudioPalette.panelSoft,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: StudioPalette.border),
              ),
              child: Text(
                item.body ?? '',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          );
        }

        return Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: StudioPalette.panelSoft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: StudioPalette.border),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: <Widget>[
                Text(
                  _eventPrefix(item, sessionUserId),
                  style: const TextStyle(
                    fontSize: 12,
                    color: StudioPalette.textMuted,
                  ),
                ),
                InkWell(
                  onTap: item.artworkId == null
                      ? null
                      : () => _openArtwork(
                            item.artworkId!,
                            fallbackTitle: item.artworkTitle,
                          ),
                  child: Text(
                    item.artworkTitle ?? 'Artwork',
                    style: const TextStyle(
                      fontSize: 12,
                      color: StudioPalette.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _eventPrefix(ChatTimelineItem item, String? sessionUserId) {
    if (item.eventType == ChatTimelineEventType.artworkCreated) {
      final actor = _displayNameForUserId(item.actorUserId ?? 'Someone');
      return '$actor created new artwork';
    }

    if (item.eventType == ChatTimelineEventType.turnStarted) {
      final target = item.targetUserId;
      if (target != null && target == sessionUserId) {
        return "It's your turn on";
      }
      if (target != null) {
        return "It's ${_displayNameForUserId(target)}'s turn on";
      }
      return "It's turn time on";
    }

    return 'Event on';
  }

  Widget _buildArtworkPane(ChatThread thread) {
    final sessionUserId = widget.controller.session?.user.id;
    final artworks = thread.artworks.toList()
      ..sort((left, right) {
        final leftMine = left.activeParticipantUserId == sessionUserId;
        final rightMine = right.activeParticipantUserId == sessionUserId;
        if (leftMine == rightMine) {
          return 0;
        }
        return leftMine ? -1 : 1;
      });

    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const StudioSectionLabel('Shared Artworks'),
          const SizedBox(height: 8),
          Expanded(
            child: artworks.isEmpty
                ? const Center(
                    child: Text(
                      'No shared artworks yet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: StudioPalette.textMuted,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: artworks.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final artwork = artworks[index];
                      final myTurn = artwork.activeParticipantUserId == sessionUserId;
                      return Material(
                        color: StudioPalette.panelSoft,
                        borderRadius: BorderRadius.circular(4),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _openArtwork(
                            artwork.id,
                            fallbackTitle: artwork.title,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: StudioPalette.border),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: <Widget>[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: myTurn
                                        ? StudioPalette.accent
                                        : StudioPalette.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        artwork.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        artwork.mode == ArtworkMode.realTime
                                            ? 'Real-time'
                                            : 'Turn-based',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: StudioPalette.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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

  Widget _buildChatPane(ChatThread thread) {
    return StudioPanel(
      child: Column(
        children: <Widget>[
          Expanded(child: _buildTimeline(thread)),
          if (_sending)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _messageController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Write a message...',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StudioButton(
                label: 'Send',
                icon: Icons.send,
                onPressed: _sending ? null : _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StudioBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: StudioPalette.textMuted),
                        ),
                      )
                    : _thread == null
                        ? const Center(
                            child: Text(
                              'Chat unavailable',
                              style: TextStyle(color: StudioPalette.textMuted),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final thread = _thread!;
                              final wideLayout = constraints.maxWidth >= 1080;

                              return Column(
                                children: <Widget>[
                                  StudioPanel(
                                    color: StudioPalette.chrome,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      children: <Widget>[
                                        StudioIconButton(
                                          icon: Icons.arrow_back,
                                          tooltip: 'Back',
                                          onPressed: () =>
                                              Navigator.of(context).maybePop(),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                thread.contact.displayName,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                'Direct chat',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: StudioPalette.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!wideLayout)
                                          StudioIconButton(
                                            icon: Icons.layers_outlined,
                                            tooltip: 'Shared artworks',
                                            active: _showMobileArtworkPane,
                                            onPressed: () {
                                              setState(() {
                                                _showMobileArtworkPane =
                                                    !_showMobileArtworkPane;
                                              });
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (!wideLayout && _showMobileArtworkPane) ...<Widget>[
                                    SizedBox(
                                      height: 220,
                                      child: _buildArtworkPane(thread),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Expanded(
                                    child: wideLayout
                                        ? Row(
                                            children: <Widget>[
                                              SizedBox(
                                                width: 320,
                                                child: _buildArtworkPane(thread),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(child: _buildChatPane(thread)),
                                            ],
                                          )
                                        : _buildChatPane(thread),
                                  ),
                                ],
                              );
                            },
                          ),
          ),
        ),
      ),
    );
  }
}
