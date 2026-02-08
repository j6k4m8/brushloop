import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image_picker/image_picker.dart';

/// Returns whether native camera capture is supported in this app runtime.
bool supportsCameraCapture() {
  if (kIsWeb) {
    return false;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// Infers an image MIME type from filename extension.
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

/// Picks an image with guardrails for unsupported sources and plugin timeouts.
Future<XFile?> pickArtworkImage({
  required ImagePicker picker,
  required ImageSource source,
}) async {
  if (source == ImageSource.camera && !supportsCameraCapture()) {
    throw StateError(
      'Camera capture is not available on this platform. Use Gallery.',
    );
  }

  try {
    if (source == ImageSource.gallery && !_preferImagePickerGallery()) {
      return await _pickGalleryViaFileSelector().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw StateError(
          'Timed out opening gallery. Please retry.',
        ),
      );
    }

    return await picker
        .pickImage(
          source: source,
          maxWidth: 3000,
          imageQuality: 95,
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw StateError(
            'Timed out opening ${source == ImageSource.camera ? 'camera' : 'gallery'}. Please retry.',
          ),
        );
  } catch (error) {
    final message = _normalizePickerError(error, source: source);
    throw StateError(message);
  }
}

Future<XFile?> _pickGalleryViaFileSelector() {
  return fs.openFile(
    acceptedTypeGroups: const <fs.XTypeGroup>[
      fs.XTypeGroup(
        label: 'Images',
        extensions: <String>[
          'png',
          'jpg',
          'jpeg',
          'webp',
          'gif',
          'heic',
          'heif',
          'bmp',
        ],
      ),
    ],
  );
}

bool _preferImagePickerGallery() {
  if (kIsWeb) {
    return false;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

String _normalizePickerError(Object error, {required ImageSource source}) {
  final raw = error.toString();

  if (raw.contains('cameraDelegate')) {
    return 'Camera capture is not configured for this platform. Use Gallery.';
  }

  if (raw.contains('Timed out opening')) {
    return raw;
  }

  final sourceLabel = source == ImageSource.camera ? 'camera' : 'gallery';
  return 'Could not open $sourceLabel: $raw';
}
