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
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
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

  /// Scale gesture start callback.
  final GestureScaleStartCallback onScaleStart;

  /// Scale gesture update callback.
  final GestureScaleUpdateCallback onScaleUpdate;

  /// Scale gesture end callback.
  final GestureScaleEndCallback onScaleEnd;

  @override
  Widget build(BuildContext context) {
    final sortedLayerIds = visibleLayerIds.toList()
      ..sort((a, b) => (layerOrder[a] ?? 0).compareTo(layerOrder[b] ?? 0));

    return GestureDetector(
      onPanStart: canEdit ? onPanStart : null,
      onPanUpdate: canEdit ? onPanUpdate : null,
      onPanEnd: canEdit ? onPanEnd : null,
      onScaleStart: canEdit ? onScaleStart : null,
      onScaleUpdate: canEdit ? onScaleUpdate : null,
      onScaleEnd: canEdit ? onScaleEnd : null,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            for (final layerId in sortedLayerIds)
              CustomPaint(
                painter: _LayerPainter(
                  layerId: layerId,
                  strokes: strokes,
                  activeStroke: activeStroke,
                ),
                child: const SizedBox.expand(),
              ),
          ],
        ),
      ),
    );
  }
}

class _LayerPainter extends CustomPainter {
  const _LayerPainter({
    required this.layerId,
    required this.strokes,
    required this.activeStroke,
  });

  final String layerId;
  final List<CanvasStroke> strokes;
  final CanvasStroke? activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // Isolate this layer in its own offscreen buffer so clear blend erasing
    // cannot leak into other layers.
    canvas.saveLayer(bounds, Paint());

    for (final stroke in strokes) {
      if (stroke.layerId != layerId) {
        continue;
      }
      _paintStroke(canvas, stroke);
    }

    if (activeStroke case final stroke?) {
      if (stroke.layerId == layerId) {
        _paintStroke(canvas, stroke);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LayerPainter oldDelegate) {
    return oldDelegate.layerId != layerId ||
        oldDelegate.strokes != strokes ||
        oldDelegate.activeStroke != activeStroke;
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
