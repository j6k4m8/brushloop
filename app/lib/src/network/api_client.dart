import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';

/// REST client for BrushLoop server endpoints.
class ApiClient {
  /// Creates an API client.
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Base server URL such as `http://127.0.0.1:8787`.
  final String baseUrl;
  final http.Client _httpClient;

  /// Creates a user account and opens a session.
  Future<SessionState> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final jsonPayload = await _requestJson(
      method: 'POST',
      path: '/api/auth/register',
      jsonBody: <String, dynamic>{
        'email': email,
        'password': password,
        'displayName': displayName,
      },
    );
    return SessionState.fromJson(jsonPayload);
  }

  /// Authenticates with email and password.
  Future<SessionState> login({
    required String email,
    required String password,
  }) async {
    final jsonPayload = await _requestJson(
      method: 'POST',
      path: '/api/auth/login',
      jsonBody: <String, dynamic>{
        'email': email,
        'password': password,
      },
    );
    return SessionState.fromJson(jsonPayload);
  }

  /// Lists accepted contacts for the current user.
  Future<List<ContactSummary>> fetchContacts({required String token}) async {
    final jsonPayload = await _requestJson(
      method: 'GET',
      path: '/api/contacts',
      token: token,
    );

    return (jsonPayload as List<dynamic>)
        .map((value) => ContactSummary.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  /// Invites a contact by email.
  Future<void> inviteContact({
    required String token,
    required String email,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/api/contacts/invite',
      token: token,
      jsonBody: <String, dynamic>{
        'inviteeEmail': email,
      },
    );
  }

  /// Lists artworks visible to the current user.
  Future<List<ArtworkSummary>> fetchArtworks({required String token}) async {
    final jsonPayload = await _requestJson(
      method: 'GET',
      path: '/api/artworks',
      token: token,
    );

    return (jsonPayload as List<dynamic>)
        .map((value) => ArtworkSummary.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  /// Loads artwork details required by the drawing screen.
  Future<ArtworkDetails> fetchArtworkDetails({
    required String token,
    required String artworkId,
  }) async {
    final jsonPayload = await _requestJson(
      method: 'GET',
      path: '/api/artworks/$artworkId',
      token: token,
    );

    return ArtworkDetails.fromJson(jsonPayload as Map<String, dynamic>);
  }

  /// Creates a new artwork with supplied participants.
  Future<void> createArtwork({
    required String token,
    required String title,
    required ArtworkMode mode,
    required List<String> participantUserIds,
    required int width,
    required int height,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/api/artworks',
      token: token,
      jsonBody: <String, dynamic>{
        'title': title,
        'mode': mode == ArtworkMode.realTime ? 'real_time' : 'turn_based',
        'participantUserIds': participantUserIds,
        'width': width,
        'height': height,
        'turnDurationMinutes': mode == ArtworkMode.turnBased ? 1440 : null,
      },
    );
  }

  /// Submits the active turn for turn-based artworks.
  Future<void> submitTurn({
    required String token,
    required String artworkId,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/api/turns/submit',
      token: token,
      jsonBody: <String, dynamic>{
        'artworkId': artworkId,
      },
    );
  }

  Future<dynamic> _requestJson({
    required String method,
    required String path,
    String? token,
    Map<String, dynamic>? jsonBody,
  }) async {
    final uri = Uri.parse('$baseUrl$path');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(jsonBody ?? <String, dynamic>{}),
        );
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }

    final payloadText = response.body.trim();
    final payload = payloadText.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(payloadText);

    if (response.statusCode >= 400) {
      throw ApiException(
        statusCode: response.statusCode,
        message: payload is Map<String, dynamic>
            ? (payload['message'] as String? ??
                payload['error'] as String? ??
                'Request failed')
            : 'Request failed',
      );
    }

    return payload;
  }
}

/// Exception thrown for non-success API responses.
class ApiException implements Exception {
  /// Creates an API exception.
  const ApiException({
    required this.statusCode,
    required this.message,
  });

  /// HTTP status code.
  final int statusCode;

  /// User-facing description.
  final String message;

  @override
  String toString() => 'ApiException(statusCode: $statusCode, message: $message)';
}
