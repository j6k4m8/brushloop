import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/models.dart';
import '../../network/collaboration_socket.dart';
import '../../state/app_controller.dart';
import '../../ui/studio_theme.dart';
import '../../widgets/drawing_canvas.dart';

/// Artwork editor screen with layer controls and drawing tools.
class ArtworkScreen extends StatefulWidget {
  /// Creates an artwork editor screen.
  const ArtworkScreen({
    super.key,
    required this.controller,
    required this.artwork,
  });

  /// App controller.
  final AppController controller;

  /// Artwork summary from the home list.
  final ArtworkSummary artwork;

  @override
  State<ArtworkScreen> createState() => _ArtworkScreenState();
}

class _ArtworkScreenState extends State<ArtworkScreen> {
  ArtworkDetails? _details;
  String? _selectedLayerId;
  bool _loading = true;
  String? _error;

  final List<CanvasStroke> _strokes = <CanvasStroke>[];
  final List<CanvasStroke> _redoBuffer = <CanvasStroke>[];
  CanvasStroke? _activeStroke;

  _EditorTool _tool = _EditorTool.brush;
  double _brushSize = 8;
  Color _brushColor = const Color(0xFF111827);

  CollaborationSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _connectSocket();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    if (_socket case final socket?) {
      socket.leaveArtwork(widget.artwork.id);
      socket.disconnect();
    }
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final details = await widget.controller.loadArtworkDetails(widget.artwork.id);
      if (!mounted) {
        return;
      }

      setState(() {
        _details = details;
        _selectedLayerId = details.layers.firstWhere(
          (layer) => !layer.isLocked,
          orElse: () => details.layers.first,
        ).id;
      });
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

  void _connectSocket() {
    final token = widget.controller.session?.token;
    if (token == null) {
      return;
    }

    final socket = CollaborationSocket(url: AppConfig.wsUrl);
    socket.connect(token: token);
    socket.joinArtwork(widget.artwork.id);

    _messageSubscription = socket.messages.listen(_handleSocketMessage);

    _socket = socket;
  }

  bool get _canEdit {
    final details = _details;
    final session = widget.controller.session;
    if (details == null || session == null) {
      return false;
    }

    if (details.artwork.mode == ArtworkMode.realTime) {
      return true;
    }

    return details.currentTurn?.activeParticipantUserId == session.user.id;
  }

  void _onPanStart(DragStartDetails details) {
    final layerId = _selectedLayerId;
    if (!_canEdit || layerId == null) {
      return;
    }

    final layer = _details?.layers.firstWhere((item) => item.id == layerId);
    if (layer == null || layer.isLocked) {
      return;
    }

    final stroke = CanvasStroke(
      id: _newStrokeId(),
      layerId: layerId,
      color: _tool == _EditorTool.eraser
          ? const Color(0x00000000)
          : _brushColor,
      size: _brushSize,
      points: <CanvasStrokePoint>[
        CanvasStrokePoint(
          x: details.localPosition.dx,
          y: details.localPosition.dy,
        ),
      ],
      isEraser: _tool == _EditorTool.eraser,
    );

    setState(() {
      _activeStroke = stroke;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final activeStroke = _activeStroke;
    if (activeStroke == null) {
      return;
    }

    final updated = CanvasStroke(
      id: activeStroke.id,
      layerId: activeStroke.layerId,
      color: activeStroke.color,
      size: activeStroke.size,
      points: <CanvasStrokePoint>[
        ...activeStroke.points,
        CanvasStrokePoint(
          x: details.localPosition.dx,
          y: details.localPosition.dy,
        ),
      ],
      isEraser: activeStroke.isEraser,
    );

    setState(() {
      _activeStroke = updated;
    });
  }

  void _onPanEnd(DragEndDetails _) {
    final activeStroke = _activeStroke;
    if (activeStroke == null) {
      return;
    }

    setState(() {
      _upsertStroke(activeStroke);
      _activeStroke = null;
      _redoBuffer.clear();
    });

    _sendStrokeOperation(activeStroke);
  }

  void _sendStrokeOperation(CanvasStroke stroke) {
    _socket?.send(<String, dynamic>{
      'type': 'client.apply_operations',
      'artworkId': widget.artwork.id,
      'operations': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': _newOperationId(),
          'artworkId': widget.artwork.id,
          'layerId': stroke.layerId,
          'actorUserId': widget.controller.session?.user.id,
          'clientId': 'flutter-client',
          'sequence': DateTime.now().microsecondsSinceEpoch,
          'lamportTs': DateTime.now().millisecondsSinceEpoch,
          'type': stroke.isEraser ? 'stroke.erase' : 'stroke.add',
          'payload': <String, dynamic>{
            'strokeId': stroke.id,
            'tool': stroke.isEraser ? 'eraser' : 'brush',
            'color':
                '#${stroke.color.toARGB32().toRadixString(16).padLeft(8, '0')}',
            'size': stroke.size,
            'opacity': 1,
            'points': stroke.points
                .map((point) => <String, dynamic>{'x': point.x, 'y': point.y})
                .toList(),
          },
        },
      ],
    });
  }

  Future<void> _submitTurn() async {
    final details = _details;
    if (details == null || details.artwork.mode != ArtworkMode.turnBased) {
      return;
    }

    try {
      final refreshed = await widget.controller.submitTurn(details.artwork.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _details = refreshed;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _undo() {
    if (_strokes.isEmpty) {
      return;
    }

    setState(() {
      final removed = _strokes.removeLast();
      _redoBuffer.add(removed);
    });
  }

  void _redo() {
    if (_redoBuffer.isEmpty) {
      return;
    }

    setState(() {
      _upsertStroke(_redoBuffer.removeLast());
    });
  }

  void _handleSocketMessage(Map<String, dynamic> payload) {
    switch (payload['type']) {
      case 'server.operations':
        _handleServerOperations(payload);
        return;
      case 'server.turn_advanced':
        _handleTurnAdvanced(payload);
        return;
      case 'server.error':
        _handleServerError(payload);
        return;
    }
  }

  void _handleServerOperations(Map<String, dynamic> payload) {
    if (payload['artworkId'] != widget.artwork.id) {
      return;
    }

    final operations = payload['operations'];
    if (operations is! List<dynamic>) {
      return;
    }

    var changed = false;
    for (final operation in operations) {
      if (operation is! Map<String, dynamic>) {
        continue;
      }

      final stroke = _strokeFromOperation(operation);
      if (stroke == null) {
        continue;
      }

      changed = _upsertStroke(stroke) || changed;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  void _handleTurnAdvanced(Map<String, dynamic> payload) {
    final details = _details;
    if (details == null || payload['artworkId'] != details.artwork.id) {
      return;
    }

    final activeParticipantUserId = payload['activeParticipantUserId'];
    final turnNumber = payload['turnNumber'];
    if (activeParticipantUserId is! String || turnNumber is! num) {
      return;
    }

    setState(() {
      _details = ArtworkDetails(
        artwork: details.artwork,
        participants: details.participants,
        layers: details.layers,
        currentTurn: TurnStatus(
          activeParticipantUserId: activeParticipantUserId,
          turnNumber: turnNumber.toInt(),
          dueAt: payload['dueAt'] as String?,
        ),
      );
    });
  }

  void _handleServerError(Map<String, dynamic> payload) {
    if (!mounted) {
      return;
    }

    final message = payload['message'];
    if (message is! String || message.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _upsertStroke(CanvasStroke stroke) {
    final existingIndex = _strokes.indexWhere((candidate) => candidate.id == stroke.id);
    if (existingIndex >= 0) {
      final existing = _strokes[existingIndex];
      if (_strokesEqual(existing, stroke)) {
        return false;
      }
      _strokes[existingIndex] = stroke;
      return true;
    }

    _strokes.add(stroke);
    return true;
  }

  bool _strokesEqual(CanvasStroke a, CanvasStroke b) {
    if (a.id != b.id ||
        a.layerId != b.layerId ||
        a.color != b.color ||
        a.size != b.size ||
        a.isEraser != b.isEraser ||
        a.points.length != b.points.length) {
      return false;
    }

    for (var i = 0; i < a.points.length; i++) {
      final left = a.points[i];
      final right = b.points[i];
      if (left.x != right.x || left.y != right.y) {
        return false;
      }
    }
    return true;
  }

  CanvasStroke? _strokeFromOperation(Map<String, dynamic> operation) {
    final type = operation['type'];
    if (type != 'stroke.add' && type != 'stroke.erase') {
      return null;
    }

    final layerId = operation['layerId'];
    final payload = operation['payload'];
    if (layerId is! String || payload is! Map<String, dynamic>) {
      return null;
    }

    final strokeId = payload['strokeId'];
    final size = payload['size'];
    final pointsRaw = payload['points'];
    if (strokeId is! String || size is! num || pointsRaw is! List<dynamic>) {
      return null;
    }

    final points = <CanvasStrokePoint>[];
    for (final rawPoint in pointsRaw) {
      if (rawPoint is! Map<String, dynamic>) {
        continue;
      }
      final x = rawPoint['x'];
      final y = rawPoint['y'];
      if (x is! num || y is! num) {
        continue;
      }

      points.add(CanvasStrokePoint(x: x.toDouble(), y: y.toDouble()));
    }

    if (points.isEmpty) {
      return null;
    }

    final operationTool = payload['tool'];
    final isEraser = type == 'stroke.erase' || operationTool == 'eraser';

    return CanvasStroke(
      id: strokeId,
      layerId: layerId,
      color: isEraser
          ? const Color(0x00000000)
          : _parseColor(payload['color'] as String?),
      size: size.toDouble(),
      points: points,
      isEraser: isEraser,
    );
  }

  Color _parseColor(String? rawColor) {
    if (rawColor == null) {
      return const Color(0xFF111827);
    }

    var value = rawColor.trim();
    if (value.startsWith('#')) {
      value = value.substring(1);
    }
    if (value.length == 6) {
      value = 'ff$value';
    }

    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) {
      return const Color(0xFF111827);
    }

    return Color(parsed);
  }

  void _toggleLayerVisibility(ArtworkLayer layer) {
    final details = _details;
    if (details == null) {
      return;
    }

    final updatedLayers = details.layers
        .map(
          (candidate) => candidate.id == layer.id
              ? candidate.copyWith(isVisible: !candidate.isVisible)
              : candidate,
        )
        .toList();

    setState(() {
      _details = ArtworkDetails(
        artwork: details.artwork,
        participants: details.participants,
        layers: updatedLayers,
        currentTurn: details.currentTurn,
      );
    });
  }

  Future<void> _addLayer() async {
    final details = _details;
    if (details == null) {
      return;
    }

    final nameController = TextEditingController();
    String? chosenName;
    bool shouldCreate = false;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return Dialog(
            child: StudioPanel(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Add Layer',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Layer name (optional)',
                      hintText: 'e.g. Shading',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      StudioButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: 8),
                      StudioButton(
                        label: 'Add',
                        onPressed: () {
                          chosenName = nameController.text.trim().isEmpty
                              ? null
                              : nameController.text.trim();
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      shouldCreate = result == true;
    } finally {
      nameController.dispose();
    }

    if (!mounted || !shouldCreate) {
      return;
    }

    try {
      final refreshed = await widget.controller.createLayer(
        artworkId: details.artwork.id,
        name: chosenName,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _details = refreshed;
        final editableLayers =
            refreshed.layers.where((layer) => !layer.isLocked).toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (editableLayers.isNotEmpty) {
          _selectedLayerId = editableLayers.last.id;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add layer: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;

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
                    : details == null
                        ? const Center(
                            child: Text(
                              'Artwork details unavailable',
                              style: TextStyle(color: StudioPalette.textMuted),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final wideLayout = constraints.maxWidth > 1150;
                              final compactLayout = constraints.maxWidth < 860;

                              return Column(
                                children: <Widget>[
                                  _buildTopToolbar(details),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: compactLayout
                                        ? Column(
                                            children: <Widget>[
                                              _buildCompactToolRow(),
                                              const SizedBox(height: 8),
                                              Expanded(child: _buildCanvas(details)),
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                height: 270,
                                                child: _buildControlsPanel(details),
                                              ),
                                            ],
                                          )
                                        : Row(
                                            children: <Widget>[
                                              SizedBox(
                                                width: 50,
                                                child: _buildToolRail(),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(child: _buildCanvas(details)),
                                              const SizedBox(width: 10),
                                              SizedBox(
                                                width: wideLayout ? 320 : 280,
                                                child: _buildControlsPanel(details),
                                              ),
                                            ],
                                          ),
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

  Widget _buildTopToolbar(ArtworkDetails details) {
    final turn = details.currentTurn;
    return StudioPanel(
      color: StudioPalette.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: <Widget>[
          StudioIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  details.artwork.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  details.artwork.mode == ArtworkMode.realTime
                      ? 'Real-time'
                      : 'Turn-based',
                  style: const TextStyle(
                    fontSize: 12,
                    color: StudioPalette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (turn != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'Turn ${turn.turnNumber}',
                style: const TextStyle(fontSize: 12, color: StudioPalette.textMuted),
              ),
            ),
          if (details.artwork.mode == ArtworkMode.turnBased)
            StudioButton(
              label: 'Submit Turn',
              icon: Icons.check,
              onPressed: _canEdit ? _submitTurn : null,
            ),
        ],
      ),
    );
  }

  Widget _buildToolRail() {
    return StudioPanel(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      color: StudioPalette.chrome,
      child: Column(
        children: <Widget>[
          StudioIconButton(
            icon: Icons.brush_outlined,
            tooltip: 'Brush',
            active: _tool == _EditorTool.brush,
            onPressed: () => setState(() => _tool = _EditorTool.brush),
          ),
          const SizedBox(height: 6),
          StudioIconButton(
            icon: Icons.auto_fix_high,
            tooltip: 'Eraser',
            active: _tool == _EditorTool.eraser,
            onPressed: () => setState(() => _tool = _EditorTool.eraser),
          ),
          const Divider(height: 14),
          StudioIconButton(
            icon: Icons.undo,
            tooltip: 'Undo',
            onPressed: _undo,
          ),
          const SizedBox(height: 6),
          StudioIconButton(
            icon: Icons.redo,
            tooltip: 'Redo',
            onPressed: _redo,
          ),
          const Spacer(),
          Icon(
            _canEdit ? Icons.lock_open_outlined : Icons.lock_outline,
            size: 16,
            color: _canEdit ? StudioPalette.success : StudioPalette.textMuted,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactToolRow() {
    return StudioPanel(
      color: StudioPalette.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: <Widget>[
          StudioIconButton(
            icon: Icons.brush_outlined,
            tooltip: 'Brush',
            active: _tool == _EditorTool.brush,
            onPressed: () => setState(() => _tool = _EditorTool.brush),
          ),
          const SizedBox(width: 6),
          StudioIconButton(
            icon: Icons.auto_fix_high,
            tooltip: 'Eraser',
            active: _tool == _EditorTool.eraser,
            onPressed: () => setState(() => _tool = _EditorTool.eraser),
          ),
          const SizedBox(width: 6),
          StudioIconButton(
            icon: Icons.undo,
            tooltip: 'Undo',
            onPressed: _undo,
          ),
          const SizedBox(width: 6),
          StudioIconButton(
            icon: Icons.redo,
            tooltip: 'Redo',
            onPressed: _redo,
          ),
          const Spacer(),
          Text(
            _canEdit ? 'Editing enabled' : 'Read-only',
            style: TextStyle(
              fontSize: 12,
              color: _canEdit ? StudioPalette.success : StudioPalette.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(ArtworkDetails details) {
    final visibleLayerIds = details.layers
        .where((layer) => layer.isVisible)
        .map((layer) => layer.id)
        .toSet();
    final layerOrder = <String, int>{
      for (final layer in details.layers) layer.id: layer.sortOrder,
    };
    final artworkAspectRatio = details.artwork.height == 0
        ? 1.0
        : details.artwork.width / details.artwork.height;

    return StudioPanel(
      color: StudioPalette.chrome,
      padding: const EdgeInsets.all(14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: StudioPalette.border),
        ),
        child: Center(
          child: AspectRatio(
            aspectRatio: artworkAspectRatio,
            child: Container(
              margin: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border.all(color: const Color(0xFFCCCCCC)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (details.artwork.basePhotoPath case final photoPath?)
                      IgnorePointer(
                        child: Image.network(
                          _resolveMediaUrl(photoPath),
                          fit: BoxFit.cover,
                          headers: <String, String>{
                            if (widget.controller.session case final session?)
                              'Authorization': 'Bearer ${session.token}',
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    DrawingCanvas(
                      strokes: _strokes,
                      activeStroke: _activeStroke,
                      visibleLayerIds: visibleLayerIds,
                      layerOrder: layerOrder,
                      canEdit: _canEdit,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _resolveMediaUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return pathOrUrl;
    }

    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
        : AppConfig.apiBaseUrl;
    final suffix = pathOrUrl.startsWith('/') ? pathOrUrl : '/$pathOrUrl';
    return '$base$suffix';
  }

  Widget _buildControlsPanel(ArtworkDetails details) {
    final palette = <Color>[
      const Color(0xFF111827),
      const Color(0xFF0E7490),
      const Color(0xFFCA8A04),
      const Color(0xFF16A34A),
      const Color(0xFFDB2777),
      const Color(0xFFEA580C),
    ];

    final turn = details.currentTurn;
    final activeUser = turn?.activeParticipantUserId;
    final displayLayers = details.layers.toList()
      ..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));

    return StudioPanel(
      child: ListView(
        children: <Widget>[
          const StudioSectionLabel('Collaboration'),
          const SizedBox(height: 6),
          Text(
            details.artwork.mode == ArtworkMode.realTime
                ? 'Mode: Real-time'
                : 'Mode: Turn-based',
            style: const TextStyle(fontSize: 12, color: StudioPalette.textMuted),
          ),
          if (turn != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Turn ${turn.turnNumber}: ${activeUser ?? 'Unknown'}\n'
                'Due: ${turn.dueAt ?? 'No timer'}',
                style: const TextStyle(fontSize: 12, color: StudioPalette.textMuted),
              ),
            ),
          const SizedBox(height: 14),
          const StudioSectionLabel('Brush'),
          const SizedBox(height: 8),
          Text(
            '${_tool == _EditorTool.eraser ? 'Eraser' : 'Brush'} Size ${_brushSize.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 12, color: StudioPalette.textMuted),
          ),
          Slider(
            value: _brushSize,
            min: 2,
            max: 36,
            onChanged: (value) {
              setState(() {
                _brushSize = value;
              });
            },
          ),
          const SizedBox(height: 6),
          const StudioSectionLabel('Color'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: palette
                .map(
                  (color) => GestureDetector(
                    onTap: _tool == _EditorTool.eraser
                        ? null
                        : () {
                            setState(() {
                              _brushColor = color;
                            });
                          },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _brushColor == color
                              ? StudioPalette.textStrong
                              : StudioPalette.border,
                          width: _brushColor == color ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const Expanded(child: StudioSectionLabel('Layers')),
              StudioIconButton(
                icon: Icons.add,
                tooltip: 'Add Layer',
                onPressed: _canEdit ? _addLayer : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final layer in displayLayers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: layer.id == _selectedLayerId
                    ? const Color(0xFF3A3A3A)
                    : StudioPalette.panelSoft,
                borderRadius: BorderRadius.circular(4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: layer.isLocked
                      ? null
                      : () {
                          setState(() {
                            _selectedLayerId = layer.id;
                          });
                        },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: layer.id == _selectedLayerId
                            ? StudioPalette.accent
                            : StudioPalette.border,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      children: <Widget>[
                        StudioIconButton(
                          icon: layer.isVisible ? Icons.visibility : Icons.visibility_off,
                          onPressed: layer.isLocked ? null : () => _toggleLayerVisibility(layer),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            layer.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: layer.isLocked
                                  ? StudioPalette.textMuted
                                  : StudioPalette.textStrong,
                            ),
                          ),
                        ),
                        if (layer.isLocked)
                          const Icon(Icons.lock_outline, size: 15, color: StudioPalette.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _newStrokeId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 31);
    return 'stroke-$now-$random';
  }

  String _newOperationId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 31);
    return 'op-$now-$random';
  }
}

enum _EditorTool {
  brush,
  eraser,
}
