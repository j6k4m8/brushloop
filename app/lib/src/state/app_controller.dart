import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../network/api_client.dart';
import 'session_storage.dart';

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
  AppController({
    required ApiClient apiClient,
    SessionStorage? sessionStorage,
  }) : _apiClient = apiClient,
       _sessionStorage = sessionStorage ?? SharedPreferencesSessionStorage();

  final ApiClient _apiClient;
  final SessionStorage _sessionStorage;

  SessionState? _session;
  bool _isRestoringSession = false;
  bool _didInitialize = false;
  bool _isBusy = false;
  String? _errorMessage;
  List<ContactSummary> _contacts = const <ContactSummary>[];
  List<PendingInvitation> _pendingInvitations = const <PendingInvitation>[];
  List<ArtworkSummary> _artworks = const <ArtworkSummary>[];

  /// Currently active session, or null when signed out.
  SessionState? get session => _session;

  /// True while a network operation is running.
  bool get isBusy => _isBusy;

  /// True while startup session restore is in progress.
  bool get isRestoringSession => _isRestoringSession;

  /// Last user-facing error.
  String? get errorMessage => _errorMessage;

  /// Loaded contact list.
  List<ContactSummary> get contacts => _contacts;

  /// Loaded pending invitation list.
  List<PendingInvitation> get pendingInvitations => _pendingInvitations;

  /// Loaded artwork summaries.
  List<ArtworkSummary> get artworks => _artworks;

  /// Restores persisted session and preloads initial home data.
  Future<void> initialize() async {
    if (_didInitialize) {
      return;
    }
    _didInitialize = true;

    _isRestoringSession = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final persisted = await _sessionStorage.readSession();
      if (persisted == null) {
        return;
      }

      _session = persisted;
      final refreshedUser = await _apiClient.fetchCurrentUser(token: persisted.token);
      _session = SessionState(
        token: persisted.token,
        user: refreshedUser,
        expiresAt: persisted.expiresAt,
      );
      await _sessionStorage.writeSession(_session!);

      await _loadHomeData();
    } catch (error) {
      if (error is ApiException && error.statusCode == 401) {
        _clearSessionState(notify: false);
        await _sessionStorage.clearSession();
        return;
      }

      _errorMessage = _toMessage(error);
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  /// Signs in with email and password and refreshes home data.
  Future<void> login({required String email, required String password}) async {
    await _runBusy(() async {
      _session = await _apiClient.login(email: email, password: password);
      await _sessionStorage.writeSession(_session!);
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
      await _sessionStorage.writeSession(_session!);
      await _loadHomeData();
    });
  }

  /// Signs out locally.
  void logout() {
    _clearSessionState(notify: true);
    unawaited(_sessionStorage.clearSession());
  }

  /// Updates the current user's display name.
  Future<void> updateDisplayName(String displayName) async {
    final token = _session?.token;
    final session = _session;
    if (token == null || session == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }

    final finalDisplayName = displayName.trim();
    if (finalDisplayName.isEmpty) {
      throw const ApiException(
        statusCode: 400,
        message: 'Display name cannot be empty',
      );
    }

    await _runBusy(() async {
      final updatedUser = await _apiClient.updateProfileDisplayName(
        token: token,
        displayName: finalDisplayName,
      );
      _session = SessionState(
        token: session.token,
        user: updatedUser,
        expiresAt: session.expiresAt,
      );
      await _sessionStorage.writeSession(_session!);
      await _loadHomeData();
    });
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

  /// Updates an artwork title and returns refreshed details.
  Future<ArtworkDetails> renameArtworkTitle({
    required String artworkId,
    required String title,
  }) async {
    final token = _session?.token;
    if (token == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }

    ArtworkDetails? refreshed;
    await _runBusy(() async {
      refreshed = await _apiClient.updateArtworkTitle(
        token: token,
        artworkId: artworkId,
        title: title,
      );
      await _loadHomeData();
    });

    if (refreshed != null) {
      return refreshed!;
    }
    return _apiClient.fetchArtworkDetails(token: token, artworkId: artworkId);
  }

  /// Loads direct chat context and timeline for one contact.
  Future<ChatThread> loadChatThread(String contactUserId) async {
    final token = _session?.token;
    if (token == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }

    return _apiClient.fetchChatThread(
      token: token,
      contactUserId: contactUserId,
    );
  }

  /// Sends a direct message to one contact.
  Future<ChatMessage> sendChatMessage({
    required String contactUserId,
    required String body,
  }) async {
    final token = _session?.token;
    if (token == null) {
      throw const ApiException(statusCode: 401, message: 'Not authenticated');
    }

    return _apiClient.sendChatMessage(
      token: token,
      contactUserId: contactUserId,
      body: body,
    );
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
      if (error is ApiException && error.statusCode == 401) {
        _clearSessionState(notify: false);
        unawaited(_sessionStorage.clearSession());
        _errorMessage = 'Session expired. Please sign in again.';
      } else {
        _errorMessage = _toMessage(error);
      }
      notifyListeners();
      rethrow;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void _clearSessionState({required bool notify}) {
    _session = null;
    _contacts = const <ContactSummary>[];
    _pendingInvitations = const <PendingInvitation>[];
    _artworks = const <ArtworkSummary>[];
    _errorMessage = null;
    if (notify) {
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
