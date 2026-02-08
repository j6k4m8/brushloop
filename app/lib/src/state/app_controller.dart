import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../network/api_client.dart';

/// Mutable app state and use-case orchestration for the BrushLoop client.
class AppController extends ChangeNotifier {
  /// Creates an app controller.
  AppController({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  SessionState? _session;
  bool _isBusy = false;
  String? _errorMessage;
  List<ContactSummary> _contacts = const <ContactSummary>[];
  List<ArtworkSummary> _artworks = const <ArtworkSummary>[];

  /// Currently active session, or null when signed out.
  SessionState? get session => _session;

  /// True while a network operation is running.
  bool get isBusy => _isBusy;

  /// Last user-facing error.
  String? get errorMessage => _errorMessage;

  /// Loaded contact list.
  List<ContactSummary> get contacts => _contacts;

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

  /// Creates a starter artwork with a selected contact.
  Future<void> createArtworkWithContact({
    required ContactSummary contact,
    required ArtworkMode mode,
  }) async {
    final token = _session?.token;
    if (token == null) {
      return;
    }

    await _runBusy(() async {
      final timestamp = DateTime.now().toIso8601String();
      final modeLabel = mode == ArtworkMode.realTime ? 'Real-time' : 'Turn-based';
      await _apiClient.createArtwork(
        token: token,
        title: '$modeLabel Sketch $timestamp',
        mode: mode,
        participantUserIds: <String>[contact.userId],
        width: 1400,
        height: 1000,
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

  Future<void> _loadHomeData() async {
    final token = _session?.token;
    if (token == null) {
      _contacts = const <ContactSummary>[];
      _artworks = const <ArtworkSummary>[];
      return;
    }

    final contacts = await _apiClient.fetchContacts(token: token);
    final artworks = await _apiClient.fetchArtworks(token: token);

    _contacts = contacts;
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
