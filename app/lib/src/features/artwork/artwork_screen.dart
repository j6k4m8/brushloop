import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

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
  bool _showMobileInspectorPane = false;
  final GlobalKey _canvasBoundaryKey = GlobalKey();
  final TransformationController _viewportController = TransformationController();
  Size _lastViewportSize = Size.zero;
  Size _lastArtworkSize = Size.zero;
  bool _viewportNeedsFit = true;
  double _minViewportScale = 0.1;
  double _maxViewportScale = 8;
  bool _pinchSizingActive = false;
  double _pinchInitialBrushSize = 8;
  bool _showBrushSizePreview = false;
  Offset? _brushPreviewPosition;
  Timer? _brushPreviewHideTimer;

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
    _brushPreviewHideTimer?.cancel();
    if (_socket case final socket?) {
      socket.leaveArtwork(widget.artwork.id);
      socket.disconnect();
    }
    _viewportController.dispose();
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
        _viewportNeedsFit = true;
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

  void _onScaleStart(ScaleStartDetails details) {
    _pinchInitialBrushSize = _brushSize;
    _pinchSizingActive = false;

    if (_tool == _EditorTool.eyedropper) {
      unawaited(_sampleColorAt(details.localFocalPoint));
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_tool != _EditorTool.brush && _tool != _EditorTool.eraser) {
      return;
    }

    final layerId = _selectedLayerId;
    if (!_canEdit || layerId == null) {
      return;
    }

    final layer = _details?.layers.firstWhere((item) => item.id == layerId);
    if (layer == null || layer.isLocked) {
      return;
    }

    if (details.pointerCount >= 2) {
      final strokeToCommit = !_pinchSizingActive ? _activeStroke : null;
      setState(() {
        if (!_pinchSizingActive) {
          _pinchSizingActive = true;
          _pinchInitialBrushSize = _brushSize;
          if (strokeToCommit != null) {
            _upsertStroke(strokeToCommit);
            _redoBuffer.clear();
          }
        }
        _activeStroke = null;
      });

      if (strokeToCommit != null) {
        _sendStrokeOperation(strokeToCommit);
      }

      final updatedSize =
          (_pinchInitialBrushSize * details.scale).clamp(2.0, 36.0).toDouble();
      _setBrushSizeAndPreview(
        updatedSize,
        localPosition: details.localFocalPoint,
        autoHide: false,
      );
      return;
    }

    if (_pinchSizingActive) {
      return;
    }

    final activeStroke = _activeStroke;
    if (activeStroke == null) {
      final stroke = CanvasStroke(
        id: _newStrokeId(),
        layerId: layerId,
        color: _tool == _EditorTool.eraser
            ? const Color(0x00000000)
            : _brushColor,
        size: _brushSize,
        points: <CanvasStrokePoint>[
          CanvasStrokePoint(
            x: details.localFocalPoint.dx,
            y: details.localFocalPoint.dy,
          ),
        ],
        isEraser: _tool == _EditorTool.eraser,
      );

      setState(() {
        _activeStroke = stroke;
      });
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
          x: details.localFocalPoint.dx,
          y: details.localFocalPoint.dy,
        ),
      ],
      isEraser: activeStroke.isEraser,
    );

    setState(() {
      _activeStroke = updated;
    });
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (!_pinchSizingActive) {
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
      return;
    }

    setState(() {
      _pinchSizingActive = false;
    });
    _scheduleBrushPreviewHide();
  }

  /// Returns the current logical artwork size in canvas coordinates.
  Size _currentArtworkSize() {
    final details = _details;
    if (details == null) {
      if (_lastArtworkSize == Size.zero) {
        return const Size(1, 1);
      }
      return _lastArtworkSize;
    }

    return Size(
      max(1, details.artwork.width).toDouble(),
      max(1, details.artwork.height).toDouble(),
    );
  }

  /// Updates brush size and displays a temporary preview circle.
  void _setBrushSizeAndPreview(
    double size, {
    Offset? localPosition,
    required bool autoHide,
  }) {
    final artworkSize = _currentArtworkSize();
    final fallback = Offset(artworkSize.width / 2, artworkSize.height / 2);
    final target = localPosition ?? fallback;
    final clampedTarget = Offset(
      target.dx.clamp(0.0, artworkSize.width).toDouble(),
      target.dy.clamp(0.0, artworkSize.height).toDouble(),
    );

    _brushPreviewHideTimer?.cancel();
    setState(() {
      _brushSize = size;
      _showBrushSizePreview = true;
      _brushPreviewPosition = clampedTarget;
    });

    if (autoHide) {
      _scheduleBrushPreviewHide();
    }
  }

  /// Schedules preview fade-out after a short inactivity delay.
  void _scheduleBrushPreviewHide() {
    _brushPreviewHideTimer?.cancel();
    _brushPreviewHideTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || !_showBrushSizePreview) {
        return;
      }

      setState(() {
        _showBrushSizePreview = false;
      });
    });
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

  Future<void> _renameArtworkTitle(ArtworkDetails details) async {
    final titleController = TextEditingController(text: details.artwork.title);
    var shouldSave = false;
    var pendingTitle = details.artwork.title;

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
                    'Rename Artwork',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                    autofocus: true,
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
                        label: 'Save',
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      shouldSave = result == true;
      pendingTitle = titleController.text.trim();
    } finally {
      titleController.dispose();
    }

    if (!shouldSave || !mounted) {
      return;
    }

    if (pendingTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title cannot be empty')),
      );
      return;
    }

    try {
      final refreshed = await widget.controller.renameArtworkTitle(
        artworkId: details.artwork.id,
        title: pendingTitle,
      );
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
        SnackBar(content: Text('Could not rename artwork: $error')),
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
                              final wideLayout = constraints.maxWidth >= 1120;

                              return Column(
                                children: <Widget>[
                                  _buildTopToolbar(
                                    details,
                                    showInspectorToggle: !wideLayout,
                                  ),
                                  const SizedBox(height: 6),
                                  _buildQuickToolRow(),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: wideLayout
                                        ? Row(
                                            children: <Widget>[
                                              Expanded(child: _buildCanvas(details)),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 300,
                                                child: _buildControlsPanel(details),
                                              ),
                                            ],
                                          )
                                        : _buildMobileWorkspace(details),
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

  Widget _buildTopToolbar(
    ArtworkDetails details, {
    required bool showInspectorToggle,
  }) {
    final turn = details.currentTurn;
    final waitingName = turn == null
        ? 'participant'
        : _displayNameForUserId(turn.activeParticipantUserId);
    final turnButtonLabel = _canEdit
        ? 'Submit Turn'
        : 'Waiting for $waitingName';
    final descriptor = _artworkDescriptor(details);
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
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        details.artwork.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    StudioIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Rename artwork',
                      onPressed: () => _renameArtworkTitle(details),
                    ),
                  ],
                ),
                Text(
                  descriptor,
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
              label: turnButtonLabel,
              icon: _canEdit ? Icons.check : Icons.hourglass_bottom,
              onPressed: _canEdit ? _submitTurn : null,
            ),
          if (showInspectorToggle) ...<Widget>[
            const SizedBox(width: 6),
            StudioIconButton(
              icon: Icons.layers_outlined,
              tooltip: 'Inspector',
              active: _showMobileInspectorPane,
              onPressed: () {
                setState(() {
                  _showMobileInspectorPane = !_showMobileInspectorPane;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  /// Resolves a user id into a UI-friendly display name when available.
  String _displayNameForUserId(String userId) {
    final sessionUser = widget.controller.session?.user;
    if (sessionUser != null && sessionUser.id == userId) {
      return sessionUser.displayName;
    }

    for (final contact in widget.controller.contacts) {
      if (contact.userId == userId) {
        return contact.displayName;
      }
    }

    if (userId.length <= 16) {
      return userId;
    }
    return '${userId.substring(0, 16)}...';
  }

  /// Builds collaboration descriptor text shown in editor header.
  String _artworkDescriptor(ArtworkDetails details) {
    final sessionUserId = widget.controller.session?.user.id;
    final collaboratorIds = details.participants
        .map((participant) => participant.userId)
        .where((userId) => userId != sessionUserId)
        .toList();

    if (collaboratorIds.isEmpty) {
      return 'Private artwork';
    }

    final collaboratorNames = collaboratorIds.map(_displayNameForUserId).toList();
    final modeLabel =
        details.artwork.mode == ArtworkMode.realTime ? 'Real-time' : 'Turn-based';
    if (collaboratorNames.length == 1) {
      return '$modeLabel with ${collaboratorNames.first}';
    }
    return '$modeLabel with ${collaboratorNames.first} +${collaboratorNames.length - 1}';
  }

  Widget _buildQuickToolRow() {
    return StudioPanel(
      color: StudioPalette.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            Tooltip(
              message: 'Color Picker',
              child: InkWell(
                onTap: _openColorPicker,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _brushColor,
                    border: Border.all(color: StudioPalette.textStrong, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
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
              icon: Icons.colorize_outlined,
              tooltip: 'Eyedropper',
              active: _tool == _EditorTool.eyedropper,
              onPressed: () => setState(() => _tool = _EditorTool.eyedropper),
            ),
            const SizedBox(width: 6),
            StudioIconButton(
              icon: Icons.open_with,
              tooltip: 'Pan / Zoom',
              active: _tool == _EditorTool.pan,
              onPressed: () => setState(() => _tool = _EditorTool.pan),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 180,
              child: Slider(
                value: _brushSize,
                min: 2,
                max: 36,
                onChanged: (value) {
                  _setBrushSizeAndPreview(
                    value,
                    autoHide: true,
                  );
                },
              ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildMobileWorkspace(ArtworkDetails details) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidth = min(320.0, constraints.maxWidth - 24);

        return Stack(
          children: <Widget>[
            Positioned.fill(child: _buildCanvas(details)),
            Align(
              alignment: Alignment.centerRight,
              child: IgnorePointer(
                ignoring: !_showMobileInspectorPane,
                child: AnimatedSlide(
                  offset: _showMobileInspectorPane
                      ? Offset.zero
                      : const Offset(1.1, 0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: paneWidth,
                      child: _buildInspectorOverlayPane(details),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: _buildMobileFab(
                icon: Icons.layers_outlined,
                active: _showMobileInspectorPane,
                onTap: () {
                  setState(() {
                    _showMobileInspectorPane = !_showMobileInspectorPane;
                  });
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMobileFab({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: active ? StudioPalette.accent : StudioPalette.panelSoft,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 20, color: StudioPalette.textStrong),
        ),
      ),
    );
  }

  Future<void> _openColorPicker() async {
    var workingColor = _brushColor;
    var applied = false;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: StudioPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Color Picker',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      ColorPicker(
                        pickerColor: workingColor,
                        enableAlpha: false,
                        portraitOnly: true,
                        labelTypes: const <ColorLabelType>[],
                        displayThumbColor: true,
                        pickerAreaHeightPercent: 0.72,
                        onColorChanged: (color) {
                          setDialogState(() {
                            workingColor = color;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          StudioButton(
                            label: 'Cancel',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 8),
                          StudioButton(
                            label: 'Apply',
                            onPressed: () {
                              applied = true;
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (applied) {
      setState(() {
        _brushColor = workingColor;
        if (_tool == _EditorTool.eyedropper) {
          _tool = _EditorTool.brush;
        }
      });
    }
  }

  Future<void> _sampleColorAt(Offset localPosition) async {
    final renderObject = _canvasBoundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      return;
    }

    try {
      final image = await renderObject.toImage(pixelRatio: 1);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        image.dispose();
        return;
      }

      final width = image.width;
      final height = image.height;
      final x = localPosition.dx.round().clamp(0, width - 1);
      final y = localPosition.dy.round().clamp(0, height - 1);
      final byteOffset = ((y * width) + x) * 4;
      if (byteOffset + 3 >= byteData.lengthInBytes) {
        image.dispose();
        return;
      }

      final r = byteData.getUint8(byteOffset);
      final g = byteData.getUint8(byteOffset + 1);
      final b = byteData.getUint8(byteOffset + 2);
      final a = byteData.getUint8(byteOffset + 3);
      image.dispose();

      if (!mounted) {
        return;
      }

      setState(() {
        _brushColor = Color.fromARGB(a, r, g, b);
        _tool = _EditorTool.brush;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eyedropper unavailable: $error')),
      );
    }
  }

  Widget _buildInspectorOverlayPane(ArtworkDetails details) {
    return StudioPanel(
      color: StudioPalette.chrome,
      child: ListView(
        children: <Widget>[
          const StudioSectionLabel('Inspector'),
          const SizedBox(height: 8),
          _buildCollaborationSection(details),
          const SizedBox(height: 12),
          _buildLayersSection(details),
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
    final artworkSize = Size(
      max(1, details.artwork.width).toDouble(),
      max(1, details.artwork.height).toDouble(),
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border.all(color: StudioPalette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          final viewportChanged = _lastViewportSize != viewportSize;
          final artworkChanged = _lastArtworkSize != artworkSize;
          if (_viewportNeedsFit || viewportChanged || artworkChanged) {
            _lastViewportSize = viewportSize;
            _lastArtworkSize = artworkSize;
            _viewportNeedsFit = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }
              _fitCanvasToViewport(viewportSize, artworkSize);
            });
          }

          return ClipRect(
            child: InteractiveViewer(
              transformationController: _viewportController,
              minScale: _minViewportScale,
              maxScale: _maxViewportScale,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(100000),
              panEnabled: _tool == _EditorTool.pan,
              scaleEnabled: _tool == _EditorTool.pan,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: artworkSize.width,
                height: artworkSize.height,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    border: Border.all(color: const Color(0xFFCCCCCC)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: RepaintBoundary(
                    key: _canvasBoundaryKey,
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
                            canEdit: _tool == _EditorTool.eyedropper ||
                                (_canEdit && _tool != _EditorTool.pan),
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onScaleEnd: _onScaleEnd,
                          ),
                          if (_showBrushSizePreview)
                            _buildBrushSizePreviewOverlay(artworkSize),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds a translucent circle preview that reflects current brush diameter.
  Widget _buildBrushSizePreviewOverlay(Size artworkSize) {
    final diameter = _brushSize.clamp(2.0, 36.0).toDouble();
    final fallback = Offset(artworkSize.width / 2, artworkSize.height / 2);
    final center = _brushPreviewPosition ?? fallback;
    final left = (center.dx - diameter / 2)
        .clamp(0.0, max(0.0, artworkSize.width - diameter))
        .toDouble();
    final top = (center.dy - diameter / 2)
        .clamp(0.0, max(0.0, artworkSize.height - diameter))
        .toDouble();

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x22000000),
            border: Border.all(color: StudioPalette.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  void _fitCanvasToViewport(Size viewportSize, Size artworkSize) {
    if (viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        artworkSize.width <= 0 ||
        artworkSize.height <= 0) {
      return;
    }

    final scale = min(
      viewportSize.width / artworkSize.width,
      viewportSize.height / artworkSize.height,
    );
    final translateX = (viewportSize.width - artworkSize.width * scale) / 2;
    final translateY = (viewportSize.height - artworkSize.height * scale) / 2;

    _minViewportScale = max(scale * 0.1, 0.02);
    _maxViewportScale = max(scale * 12, 6);
    _viewportController.value = Matrix4.identity()
      ..translateByDouble(translateX, translateY, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
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
    return StudioPanel(
      child: ListView(
        children: <Widget>[
          const StudioSectionLabel('Inspector'),
          const SizedBox(height: 8),
          _buildCollaborationSection(details),
          const SizedBox(height: 14),
          _buildLayersSection(details),
        ],
      ),
    );
  }

  Widget _buildCollaborationSection(ArtworkDetails details) {
    final turn = details.currentTurn;
    final activeUser = turn?.activeParticipantUserId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
      ],
    );
  }

  Widget _buildLayersSection(ArtworkDetails details) {
    final displayLayers = details.layers.toList()
      ..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));

    return Column(
      children: <Widget>[
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
  eyedropper,
  pan,
}
