import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../network/api_client.dart';

/// Local base-photo payload selected before artwork creation.
class ArtworkBasePhotoInput {
  /// Creates a base-photo upload payload.
  const ArtworkBasePhotoInput({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });

  /// Raw image bytes.
  final Uint8List bytes;

  /// Original filename from picker/camera.
  final String filename;

  /// MIME type for upload.
  final String mimeType;
}

/// Mutable app state and use-case orchestration for the BrushLoop client.
class AppController extends ChangeNotifier {
  /// Creates an app controller.
  AppController({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  SessionState? _session;
  bool _isBusy = false;
  String? _errorMessage;
  List<ContactSummary> _contacts = const <ContactSummary>[];
  List<PendingInvitation> _pendingInvitations = const <PendingInvitation>[];
  List<ArtworkSummary> _artworks = const <ArtworkSummary>[];

  /// Currently active session, or null when signed out.
  SessionState? get session => _session;

  /// True while a network operation is running.
  bool get isBusy => _isBusy;

  /// Last user-facing error.
  String? get errorMessage => _errorMessage;

  /// Loaded contact list.
  List<ContactSummary> get contacts => _contacts;

  /// Loaded pending invitation list.
  List<PendingInvitation> get pendingInvitations => _pendingInvitations;

  /// Loaded artwork summaries.
  List<ArtworkSummary> get artworks => _artworks;

  /// Signs in with email and password and refreshes home data.
  Future<void> login({required String email, required String password}) async {
    await _runBusy(() async {
      _session = await _apiClient.login(email: email, password: password);
      await _loadHomeData();
    });
  }

  /// Registers a new account and refreshes home data.
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _runBusy(() async {
      _session = await _apiClient.register(
        email: email,
        password: password,
        displayName: displayName,
      );
      await _loadHomeData();
    });
  }

  /// Signs out locally.
  void logout() {
    _session = null;
    _contacts = const <ContactSummary>[];
    _pendingInvitations = const <PendingInvitation>[];
    _artworks = const <ArtworkSummary>[];
    _errorMessage = null;
    notifyListeners();
  }

  /// Refreshes contacts and artworks.
  Future<void> refreshHome() async {
    await _runBusy(_loadHomeData);
  }

  /// Invites a contact by email and refreshes lists.
  Future<void> inviteContact(String email) async {
    final token = _session?.token;
    if (token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.inviteContact(token: token, email: email);
      await _loadHomeData();
    });
  }

  /// Accepts a pending invitation and refreshes home data.
  Future<void> acceptInvitation(String invitationId) async {
    final token = _session?.token;
    if (token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.acceptInvitation(
        token: token,
        invitationId: invitationId,
      );
      await _loadHomeData();
    });
  }

  /// Declines a pending invitation and refreshes home data.
  Future<void> declineInvitation(String invitationId) async {
    final token = _session?.token;
    if (token == null) {
      return;
    }

    await _runBusy(() async {
      await _apiClient.declineInvitation(
        token: token,
        invitationId: invitationId,
      );
      await _loadHomeData();
    });
  }

  /// Creates a starter artwork with optional collaborator contact.
  Future<void> createArtwork({
    required ArtworkMode mode,
    ContactSummary? collaborator,
    String? firstTurnUserId,
    ArtworkBasePhotoInput? basePhoto,
  }) async {
    final token = _session?.token;
    if (token == null) {
      return;
    }

    await _runBusy(() async {
      final timestamp = DateTime.now().toIso8601String();
      final modeLabel = mode == ArtworkMode.realTime ? 'Real-time' : 'Turn-based';
      String? basePhotoPath;

      if (basePhoto != null) {
        final uploaded = await _apiClient.uploadMedia(
          token: token,
          bytes: basePhoto.bytes,
          mimeType: basePhoto.mimeType,
          filename: basePhoto.filename,
        );
        basePhotoPath = uploaded.contentPath;
      }

      await _apiClient.createArtwork(
        token: token,
        title: '$modeLabel Sketch $timestamp',
        mode: mode,
        participantUserIds: collaborator == null
            ? const <String>[]
            : <String>[collaborator.userId],
        firstTurnUserId: firstTurnUserId,
        width: 1400,
        height: 1000,
        basePhotoPath: basePhotoPath,
      );
      await _loadHomeData();
    });
  }

  /// Loads a single artwork payload.
  Future<ArtworkDetails> loadArtworkDetails(String artworkId) async {
    final token = _session?.token;
    if (token == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }

    return _apiClient.fetchArtworkDetails(token: token, artworkId: artworkId);
  }

  /// Submits the active turn and refreshes details.
  Future<ArtworkDetails> submitTurn(String artworkId) async {
    final token = _session?.token;
    if (token == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }

    await _runBusy(() async {
      await _apiClient.submitTurn(token: token, artworkId: artworkId);
      await _loadHomeData();
    });

    return _apiClient.fetchArtworkDetails(token: token, artworkId: artworkId);
  }

  /// Adds a new layer and returns refreshed artwork details.
  Future<ArtworkDetails> createLayer({
    required String artworkId,
    String? name,
  }) async {
    final token = _session?.token;
    if (token == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }

    await _runBusy(() async {
      await _apiClient.createLayer(
        token: token,
        artworkId: artworkId,
        name: name,
      );
      await _loadHomeData();
    });

    return _apiClient.fetchArtworkDetails(token: token, artworkId: artworkId);
  }

  Future<void> _loadHomeData() async {
    final token = _session?.token;
    if (token == null) {
      _contacts = const <ContactSummary>[];
      _pendingInvitations = const <PendingInvitation>[];
      _artworks = const <ArtworkSummary>[];
      return;
    }

    final contacts = await _apiClient.fetchContacts(token: token);
    final pendingInvitations = await _apiClient.fetchPendingInvitations(
      token: token,
    );
    final artworks = await _apiClient.fetchArtworks(token: token);

    _contacts = contacts;
    _pendingInvitations = pendingInvitations;
    _artworks = artworks;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await action();
    } catch (error) {
      _errorMessage = _toMessage(error);
      notifyListeners();
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  String _toMessage(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return error.toString();
  }
}
