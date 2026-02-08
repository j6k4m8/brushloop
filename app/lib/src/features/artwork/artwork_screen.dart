import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/models.dart';
import '../../network/collaboration_socket.dart';
import '../../state/app_controller.dart';
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
          return AlertDialog(
            title: const Text('Add Layer'),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Layer name (optional)',
                hintText: 'e.g. Shading',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  chosenName = nameController.text.trim().isEmpty
                      ? null
                      : nameController.text.trim();
                  Navigator.of(context).pop(true);
                },
                child: const Text('Add'),
              ),
            ],
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
      appBar: AppBar(
        title: Text(widget.artwork.title),
        actions: <Widget>[
          IconButton(
            onPressed: _undo,
            tooltip: 'Undo',
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            onPressed: _redo,
            tooltip: 'Redo',
            icon: const Icon(Icons.redo),
          ),
          if (details?.artwork.mode == ArtworkMode.turnBased)
            FilledButton.icon(
              onPressed: _canEdit ? _submitTurn : null,
              icon: const Icon(Icons.check),
              label: const Text('Submit Turn'),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : details == null
                  ? const Center(child: Text('Artwork details unavailable'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final controls = _buildControlsPanel(context, details);
                        final canvas = _buildCanvas(details);

                        if (constraints.maxWidth > 980) {
                          return Row(
                            children: <Widget>[
                              SizedBox(width: 320, child: controls),
                              const VerticalDivider(width: 1),
                              Expanded(child: canvas),
                            ],
                          );
                        }

                        return Column(
                          children: <Widget>[
                            SizedBox(height: 260, child: controls),
                            const Divider(height: 1),
                            Expanded(child: canvas),
                          ],
                        );
                      },
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

    return Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD4D4D8)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
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

  Widget _buildControlsPanel(BuildContext context, ArtworkDetails details) {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Collaboration', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Chip(
          label: Text(
            details.artwork.mode == ArtworkMode.realTime
                ? 'Mode: Real-time'
                : 'Mode: Turn-based',
          ),
        ),
        if (turn != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Turn ${turn.turnNumber}: ${activeUser ?? 'Unknown'}\n'
              'Due: ${turn.dueAt ?? 'No timer'}',
            ),
          ),
        const SizedBox(height: 20),
        Text('Tools', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<_EditorTool>(
          segments: const <ButtonSegment<_EditorTool>>[
            ButtonSegment<_EditorTool>(
              value: _EditorTool.brush,
              label: Text('Brush'),
              icon: Icon(Icons.brush_outlined),
            ),
            ButtonSegment<_EditorTool>(
              value: _EditorTool.eraser,
              label: Text('Eraser'),
              icon: Icon(Icons.auto_fix_high),
            ),
          ],
          selected: <_EditorTool>{_tool},
          onSelectionChanged: (value) {
            setState(() {
              _tool = value.first;
            });
          },
        ),
        const SizedBox(height: 12),
        Text(
          '${_tool == _EditorTool.eraser ? 'Eraser' : 'Brush'} Size '
          '${_brushSize.toStringAsFixed(0)}',
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
        const SizedBox(height: 8),
        Text('Color', style: Theme.of(context).textTheme.titleSmall),
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _brushColor == color
                            ? Colors.black
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Layers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: _canEdit ? _addLayer : null,
              icon: const Icon(Icons.add),
              tooltip: 'Add Layer',
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final layer in displayLayers)
          Card(
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 2,
              ),
              minLeadingWidth: 28,
              leading: IconButton(
                onPressed:
                    layer.isLocked ? null : () => _toggleLayerVisibility(layer),
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(
                  layer.isVisible ? Icons.visibility : Icons.visibility_off,
                ),
              ),
              title: Text(layer.name),
              trailing: layer.id == _selectedLayerId
                  ? const Icon(Icons.check_circle, size: 18)
                  : const Icon(Icons.radio_button_unchecked, size: 18),
              onTap: layer.isLocked
                  ? null
                  : () {
                      setState(() {
                        _selectedLayerId = layer.id;
                      });
                    },
            ),
          ),
      ],
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
