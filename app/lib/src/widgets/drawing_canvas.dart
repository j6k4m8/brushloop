import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';

/// A sampled point in a vector stroke.
class CanvasStrokePoint {
  /// Creates a stroke point.
  const CanvasStrokePoint({
    required this.x,
    required this.y,
  });

  /// Horizontal position in local canvas coordinates.
  final double x;

  /// Vertical position in local canvas coordinates.
  final double y;

  /// Converts this point to an [Offset].
  Offset toOffset() => Offset(x, y);
}

/// A user-drawn stroke rendered in vector space.
class CanvasStroke {
  /// Creates a stroke.
  const CanvasStroke({
    required this.id,
    required this.layerId,
    required this.color,
    required this.size,
    required this.points,
    required this.isEraser,
  });

  /// Unique stroke id.
  final String id;

  /// Owning layer id.
  final String layerId;

  /// Stroke color.
  final Color color;

  /// Brush width.
  final double size;

  /// Ordered stroke points.
  final List<CanvasStrokePoint> points;

  /// True when this stroke represents an eraser action.
  final bool isEraser;
}

/// Interactive drawing surface used by the artwork screen.
class DrawingCanvas extends StatelessWidget {
  /// Creates a drawing canvas.
  const DrawingCanvas({
    super.key,
    required this.strokes,
    required this.activeStroke,
    required this.visibleLayerIds,
    required this.layerOrder,
    required this.canEdit,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  /// Persisted strokes.
  final List<CanvasStroke> strokes;

  /// In-progress stroke being drawn by the user.
  final CanvasStroke? activeStroke;

  /// Layers currently visible on screen.
  final Set<String> visibleLayerIds;

  /// Layer sorting table from id to order index.
  final Map<String, int> layerOrder;

  /// True when editing interactions are allowed.
  final bool canEdit;

  /// Start gesture callback.
  final GestureDragStartCallback onPanStart;

  /// Update gesture callback.
  final GestureDragUpdateCallback onPanUpdate;

  /// End gesture callback.
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    final painter = _DrawingPainter(
      strokes: strokes,
      activeStroke: activeStroke,
      visibleLayerIds: visibleLayerIds,
      layerOrder: layerOrder,
    );

    return GestureDetector(
      onPanStart: canEdit ? onPanStart : null,
      onPanUpdate: canEdit ? onPanUpdate : null,
      onPanEnd: canEdit ? onPanEnd : null,
      child: CustomPaint(
        painter: painter,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  const _DrawingPainter({
    required this.strokes,
    required this.activeStroke,
    required this.visibleLayerIds,
    required this.layerOrder,
  });

  final List<CanvasStroke> strokes;
  final CanvasStroke? activeStroke;
  final Set<String> visibleLayerIds;
  final Map<String, int> layerOrder;

  @override
  void paint(Canvas canvas, Size size) {
    final layerIds = visibleLayerIds.toList()
      ..sort((a, b) => (layerOrder[a] ?? 0).compareTo(layerOrder[b] ?? 0));

    for (final layerId in layerIds) {
      // Draw each layer into an offscreen picture so erasing cannot modify
      // already-composited lower layers.
      final recorder = PictureRecorder();
      final layerCanvas = Canvas(recorder);

      for (final stroke in strokes) {
        if (stroke.layerId != layerId) {
          continue;
        }
        _paintStroke(layerCanvas, stroke);
      }

      if (activeStroke case final stroke?) {
        if (stroke.layerId == layerId) {
          _paintStroke(layerCanvas, stroke);
        }
      }

      final picture = recorder.endRecording();
      canvas.drawPicture(picture);
      picture.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.visibleLayerIds != visibleLayerIds ||
        oldDelegate.layerOrder != layerOrder;
  }

  void _paintStroke(Canvas canvas, CanvasStroke stroke) {
    if (stroke.points.isEmpty) {
      return;
    }

    final paint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = stroke.size
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver
      ..color = stroke.isEraser ? const Color(0xFFFFFFFF) : stroke.color;

    if (stroke.points.length == 1) {
      final center = stroke.points.single.toOffset();
      canvas.drawCircle(center, stroke.size / 2, paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
    for (final point in stroke.points.skip(1)) {
      path.lineTo(point.x, point.y);
    }

    canvas.drawPath(path, paint);
  }
}
