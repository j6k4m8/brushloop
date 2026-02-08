/// Authenticated user profile.
class SessionUser {
  /// Creates a user profile.
  const SessionUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  /// User id.
  final String id;

  /// User email address.
  final String email;

  /// Display name used in the UI.
  final String displayName;

  /// Decode from JSON.
  factory SessionUser.fromJson(Map<String, dynamic> json) {
    return SessionUser(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
    );
  }
}

/// Session data returned after login or registration.
class SessionState {
  /// Creates session state.
  const SessionState({
    required this.token,
    required this.user,
    required this.expiresAt,
  });

  /// Bearer token.
  final String token;

  /// Signed-in user profile.
  final SessionUser user;

  /// Expiry timestamp (ISO-8601).
  final String expiresAt;

  /// Decode from JSON.
  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      token: json['token'] as String,
      user: SessionUser.fromJson(json['user'] as Map<String, dynamic>),
      expiresAt: json['expiresAt'] as String,
    );
  }
}

/// Contact entry shown on the home screen.
class ContactSummary {
  /// Creates a contact summary.
  const ContactSummary({
    required this.userId,
    required this.displayName,
    required this.email,
  });

  /// Contact user id.
  final String userId;

  /// Contact display name.
  final String displayName;

  /// Contact email.
  final String email;

  /// Decode from JSON.
  factory ContactSummary.fromJson(Map<String, dynamic> json) {
    return ContactSummary(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String,
    );
  }
}

/// Pending invitation entry awaiting user action.
class PendingInvitation {
  /// Creates a pending invitation model.
  const PendingInvitation({
    required this.id,
    required this.inviterUserId,
    required this.inviterDisplayName,
    required this.inviterEmail,
    required this.createdAt,
  });

  /// Invitation id.
  final String id;

  /// Inviter user id.
  final String inviterUserId;

  /// Inviter display name.
  final String inviterDisplayName;

  /// Inviter email address, if available.
  final String? inviterEmail;

  /// Creation timestamp.
  final String createdAt;

  /// Decode from JSON.
  factory PendingInvitation.fromJson(Map<String, dynamic> json) {
    return PendingInvitation(
      id: json['id'] as String,
      inviterUserId: json['inviterUserId'] as String,
      inviterDisplayName: (json['inviterDisplayName'] as String?) ?? 'Unknown',
      inviterEmail: json['inviterEmail'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }
}

/// Collaboration mode for an artwork.
enum ArtworkMode {
  /// Simultaneous editing.
  realTime,

  /// Round-robin turn based editing.
  turnBased,
}

/// Home list item for an artwork.
class ArtworkSummary {
  /// Creates an artwork list item.
  const ArtworkSummary({
    required this.id,
    required this.title,
    required this.mode,
    required this.participantUserIds,
    required this.activeParticipantUserId,
  });

  /// Artwork id.
  final String id;

  /// Artwork title.
  final String title;

  /// Collaboration mode.
  final ArtworkMode mode;

  /// Ordered participant ids.
  final List<String> participantUserIds;

  /// Active turn owner if the artwork is turn based.
  final String? activeParticipantUserId;

  /// Decode from JSON.
  factory ArtworkSummary.fromJson(Map<String, dynamic> json) {
    return ArtworkSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      mode: _decodeMode(json['mode'] as String),
      participantUserIds:
          (json['participantUserIds'] as List<dynamic>).cast<String>(),
      activeParticipantUserId: json['activeParticipantUserId'] as String?,
    );
  }
}

/// Artwork metadata included in detailed payloads.
class ArtworkMeta {
  /// Creates artwork metadata.
  const ArtworkMeta({
    required this.id,
    required this.title,
    required this.mode,
    required this.width,
    required this.height,
    required this.basePhotoPath,
  });

  /// Artwork id.
  final String id;

  /// Title shown in lists and editor.
  final String title;

  /// Mode for collaboration and UI behavior.
  final ArtworkMode mode;

  /// Canvas width.
  final int width;

  /// Canvas height.
  final int height;

  /// Optional server path for the base photo layer.
  final String? basePhotoPath;

  /// Decode from JSON.
  factory ArtworkMeta.fromJson(Map<String, dynamic> json) {
    return ArtworkMeta(
      id: json['id'] as String,
      title: json['title'] as String,
      mode: _decodeMode(json['mode'] as String),
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      basePhotoPath: json['basePhotoPath'] as String?,
    );
  }
}

/// Participant ordering entry for turn flow.
class ArtworkParticipant {
  /// Creates a participant entry.
  const ArtworkParticipant({
    required this.userId,
    required this.turnIndex,
  });

  /// Participant user id.
  final String userId;

  /// Turn order index.
  final int turnIndex;

  /// Decode from JSON.
  factory ArtworkParticipant.fromJson(Map<String, dynamic> json) {
    return ArtworkParticipant(
      userId: json['userId'] as String,
      turnIndex: (json['turnIndex'] as num).toInt(),
    );
  }
}

/// Layer model used by the drawing screen.
class ArtworkLayer {
  /// Creates a layer.
  const ArtworkLayer({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isVisible,
    required this.isLocked,
  });

  /// Layer id.
  final String id;

  /// User-facing name.
  final String name;

  /// Sort order from back to front.
  final int sortOrder;

  /// Visibility flag.
  final bool isVisible;

  /// Lock flag.
  final bool isLocked;

  /// Returns a copied layer with updated visibility.
  ArtworkLayer copyWith({bool? isVisible}) {
    return ArtworkLayer(
      id: id,
      name: name,
      sortOrder: sortOrder,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked,
    );
  }

  /// Decode from JSON.
  factory ArtworkLayer.fromJson(Map<String, dynamic> json) {
    return ArtworkLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: (json['sortOrder'] as num).toInt(),
      isVisible: json['isVisible'] as bool,
      isLocked: json['isLocked'] as bool,
    );
  }
}

/// Turn status used for turn-based collaboration hints.
class TurnStatus {
  /// Creates turn status.
  const TurnStatus({
    required this.activeParticipantUserId,
    required this.turnNumber,
    required this.dueAt,
  });

  /// Current active user id.
  final String activeParticipantUserId;

  /// Monotonic turn number.
  final int turnNumber;

  /// Optional due date.
  final String? dueAt;

  /// Decode from JSON.
  factory TurnStatus.fromJson(Map<String, dynamic> json) {
    return TurnStatus(
      activeParticipantUserId: json['activeParticipantUserId'] as String,
      turnNumber: (json['turnNumber'] as num).toInt(),
      dueAt: json['dueAt'] as String?,
    );
  }
}

/// Detailed artwork payload for the editor screen.
class ArtworkDetails {
  /// Creates artwork details.
  const ArtworkDetails({
    required this.artwork,
    required this.participants,
    required this.layers,
    required this.currentTurn,
  });

  /// Artwork metadata.
  final ArtworkMeta artwork;

  /// Ordered participants.
  final List<ArtworkParticipant> participants;

  /// Layer stack.
  final List<ArtworkLayer> layers;

  /// Current turn state when in turn-based mode.
  final TurnStatus? currentTurn;

  /// Decode from JSON.
  factory ArtworkDetails.fromJson(Map<String, dynamic> json) {
    return ArtworkDetails(
      artwork: ArtworkMeta.fromJson(json['artwork'] as Map<String, dynamic>),
      participants: (json['participants'] as List<dynamic>)
          .map((value) =>
              ArtworkParticipant.fromJson(value as Map<String, dynamic>))
          .toList(),
      layers: (json['layers'] as List<dynamic>)
          .map((value) => ArtworkLayer.fromJson(value as Map<String, dynamic>))
          .toList(),
      currentTurn: json['currentTurn'] == null
          ? null
          : TurnStatus.fromJson(json['currentTurn'] as Map<String, dynamic>),
    );
  }
}

/// Stored media metadata returned after upload.
class UploadedMedia {
  /// Creates an uploaded media payload.
  const UploadedMedia({
    required this.id,
    required this.contentPath,
    required this.mimeType,
    required this.originalFilename,
    required this.byteSize,
  });

  /// Media id.
  final String id;

  /// API path that serves content bytes.
  final String contentPath;

  /// Media mime type.
  final String mimeType;

  /// Original filename from client.
  final String originalFilename;

  /// Byte size stored on server.
  final int byteSize;

  /// Decode from JSON.
  factory UploadedMedia.fromJson(Map<String, dynamic> json) {
    return UploadedMedia(
      id: json['id'] as String,
      contentPath: json['contentPath'] as String,
      mimeType: json['mimeType'] as String,
      originalFilename: json['originalFilename'] as String,
      byteSize: (json['byteSize'] as num).toInt(),
    );
  }
}

ArtworkMode _decodeMode(String raw) {
  switch (raw) {
    case 'real_time':
      return ArtworkMode.realTime;
    case 'turn_based':
      return ArtworkMode.turnBased;
    default:
      throw ArgumentError('Unsupported artwork mode: $raw');
  }
}
