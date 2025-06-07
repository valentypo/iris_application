import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ObjectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ObjectDetection({super.key, required this.cameras});

  @override
  State<ObjectDetection> createState() => _ObjectDetectionState();
}

class _ObjectDetectionState extends State<ObjectDetection> with WidgetsBindingObserver {
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  
  CameraDescription? _currentCamera;
  CameraDescription? _frontCamera;
  CameraDescription? _backCamera;
  
  String result = "Initializing...";
  File? _imageFile;
  List<DetectedObject> _detectedObjects = [];
  Size? _imageSize;
  final ImagePicker _picker = ImagePicker();
  
  // Zoom state
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  
  // Flash state
  FlashMode _currentFlashMode = FlashMode.off;
  final List<FlashMode> _flashModes = [
    FlashMode.off,
    FlashMode.auto,
    FlashMode.always
  ];
  int _currentFlashModeIndex = 0;
  
  // Focus state
  Offset? _focusPoint;
  Timer? _focusPointTimer;
  
  // Key for the preview container
  final GlobalKey _previewContainerKey = GlobalKey();
  
  // For draggable sheet
  DraggableScrollableController _dragController = DraggableScrollableController();
  double _initialChildSize = 0.3;
  double _minChildSize = 0.3;
  double _maxChildSize = 0.8;
  bool _showDraggable = false;

  // Change this to your computer's IP address when testing on physical device
  static const String baseUrl = 'http://172.20.10.5:5000';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkBackendConnection();
    if (widget.cameras.isNotEmpty) {
      _setupCamerasAndInitialize();
    }
  }

  void _setupCamerasAndInitialize() {
    for (var cameraDescription in widget.cameras) {
      if (cameraDescription.lensDirection == CameraLensDirection.back) {
        _backCamera = cameraDescription;
      } else if (cameraDescription.lensDirection == CameraLensDirection.front) {
        _frontCamera = cameraDescription;
      }
    }
    _currentCamera = _backCamera ?? _frontCamera ?? widget.cameras.first;
    if (_currentCamera != null) {
      _initializeCamera(_currentCamera!);
    }
  }

  Future<void> _checkBackendConnection() async {
    try {
      setState(() {
        result = "Connecting to YOLO backend...";
      });

      final response = await http.get(
        Uri.parse('$baseUrl/health'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          result = "Tap the button to detect objects";
        });
      } else {
        setState(() {
          result = "Backend connection failed. Check if Python server is running.";
        });
      }
    } catch (e) {
      setState(() {
        result = "Cannot connect to backend. Make sure Python server is running.";
      });
      print("Backend connection error: $e");
    }
  }

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }
    
    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    if (mounted) setState(() => _isCameraInitialized = false);
    _currentZoomLevel = 1.0;

    _initializeControllerFuture = _cameraController!.initialize();

    try {
      await _initializeControllerFuture;
      if (!mounted) return;

      // Fetch zoom levels
      _minZoomLevel = await _cameraController!.getMinZoomLevel();
      _maxZoomLevel = await _cameraController!.getMaxZoomLevel();

      // Set initial flash mode
      await _cameraController!.setFlashMode(_currentFlashMode);

      setState(() {
        _isCameraInitialized = true;
        _currentCamera = cameraDescription;
        result = "Tap the button to detect objects";
      });
    } catch (e) {
      print('Error initializing camera: $e');
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = false;
        result = "Camera initialization failed: $e";
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusPointTimer?.cancel();
    _cameraController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _dragController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null ||
        !cameraController.value.isInitialized ||
        _currentCamera == null) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
      if (mounted) setState(() => _isCameraInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      if (!_isCameraInitialized) {
        _initializeCamera(_currentCamera!);
      }
    }
  }

  void _flipCamera() {
    if (_isProcessing || _frontCamera == null || _backCamera == null) return;
    final newCamera =
        (_cameraController!.description.lensDirection == CameraLensDirection.back)
            ? _frontCamera!
            : _backCamera!;
    _initializeCamera(newCamera);
  }

  Future<void> _pickImageFromGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        _imageFile = File(image.path);
        await _processImage();
      }
    } catch (e) {
      setState(() {
        result = "Failed to pick image: $e";
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _takePicture() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isProcessing ||
        _cameraController!.value.isTakingPicture) {
      return;
    }
    
    setState(() => _isProcessing = true);
    try {
      // Ensure flash mode is set
      await _cameraController!.setFlashMode(_currentFlashMode);
      // Ensure zoom level is set
      await _cameraController!.setZoomLevel(_currentZoomLevel);
      
      final XFile picture = await _cameraController!.takePicture();
      _imageFile = File(picture.path);
      await _processImage();
    } catch (e) {
      setState(() {
        result = "Failed to take picture: $e";
      });
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processImage() async {
    if (_imageFile == null) return;

    setState(() {
      _isProcessing = true;
      result = "Analyzing image...";
      _detectedObjects = [];
      _showDraggable = true;
    });

    try {
      // Get image dimensions
      final decodedImage = await decodeImageFromList(await _imageFile!.readAsBytes());
      _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());

      // Convert image to base64
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Send to backend
      final response = await http.post(
        Uri.parse('$baseUrl/detect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          List<DetectedObject> detectedObjects = [];
          
          for (var detection in data['detections']) {
            final bbox = detection['bbox'] as List;
            final rect = Rect.fromLTRB(
              bbox[0].toDouble(),
              bbox[1].toDouble(),
              bbox[2].toDouble(),
              bbox[3].toDouble(),
            );

            detectedObjects.add(DetectedObject(
              boundingBox: rect,
              label: detection['class'],
              confidence: detection['confidence'].toDouble(),
            ));
          }

          setState(() {
            _detectedObjects = detectedObjects;
            if (detectedObjects.isEmpty) {
              result = "No objects detected. Try different angle or lighting.";
            } else {
              result = "Found ${detectedObjects.length} object(s)";
              // Expand the sheet when objects are detected
              _dragController.animateTo(
                0.5,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        } else {
          setState(() {
            result = "Detection failed: ${data['error']}";
          });
        }
      } else {
        setState(() {
          result = "Server error: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        result = "Detection failed: $e";
      });
      print("Detection error: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _resetDetection() {
    setState(() {
      _imageFile = null;
      _detectedObjects = [];
      result = "Tap the button to detect objects";
      _showDraggable = false;
    });
    _dragController.animateTo(
      _minChildSize,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // --- Zoom ---
  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = _currentZoomLevel;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    double newZoomLevel =
        (_baseZoomLevel * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
    if (newZoomLevel != _currentZoomLevel) {
      await _cameraController!.setZoomLevel(newZoomLevel);
      if (mounted) setState(() => _currentZoomLevel = newZoomLevel);
    }
  }

  // --- Flash ---
  IconData _getFlashIcon() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
      default:
        return Icons.flash_off;
    }
  }

  void _toggleFlashMode() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    _currentFlashModeIndex = (_currentFlashModeIndex + 1) % _flashModes.length;
    _currentFlashMode = _flashModes[_currentFlashModeIndex];
    try {
      await _cameraController!.setFlashMode(_currentFlashMode);
      if (mounted) setState(() {});
      print("Flash mode set to: $_currentFlashMode");
    } catch (e) {
      print("Error setting flash mode: $e");
    }
  }

  // --- Focus ---
  Future<void> _handleTapToFocus(TapUpDetails details) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    final RenderBox? previewBox =
        _previewContainerKey.currentContext?.findRenderObject() as RenderBox?;
    if (previewBox == null || !previewBox.hasSize) return;

    final Offset localOffset = previewBox.globalToLocal(details.globalPosition);

    final double x = (localOffset.dx / previewBox.size.width).clamp(0.0, 1.0);
    final double y = (localOffset.dy / previewBox.size.height).clamp(0.0, 1.0);
    final Offset tapPoint = Offset(x, y);

    try {
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setFocusPoint(tapPoint);

      print("Focus point set to: $tapPoint");

      if (mounted) {
        setState(() {
          _focusPoint = localOffset;
        });
        _focusPointTimer?.cancel();
        _focusPointTimer = Timer(const Duration(seconds: 1), () {
          if (mounted) setState(() => _focusPoint = null);
        });
      }
    } catch (e) {
      print("Error setting focus point: $e");
    }
  }

  Widget _buildCameraPreview(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.width * _cameraController!.value.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: _previewContainerKey,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapUp: _handleTapToFocus,
                  child: CameraPreview(_cameraController!),
                ),
                if (_focusPoint != null)
                  Positioned(
                    left: _focusPoint!.dx - 30,
                    top: _focusPoint!.dy - 30,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.yellow, width: 2),
                        shape: BoxShape.rectangle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goBack() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen camera preview or image
          Positioned.fill(
            child: _imageFile != null
                ? Image.file(
                    _imageFile!,
                    fit: BoxFit.contain,
                  )
                : FutureBuilder<void>(
                    future: _initializeControllerFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          _isCameraInitialized) {
                        return _buildCameraPreview(context);
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              "Error loading camera: ${snapshot.error}",
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                  ),
          ),

          // Bounding boxes overlay
          if (_imageFile != null && _detectedObjects.isNotEmpty && _imageSize != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final widthRatio = constraints.maxWidth / _imageSize!.width;
                  final heightRatio = constraints.maxHeight / _imageSize!.height;
                  final scale = widthRatio < heightRatio ? widthRatio : heightRatio;
                  
                  return CustomPaint(
                    painter: ObjectDetectorPainter(
                      _detectedObjects,
                      scale,
                      _imageSize!,
                      constraints.biggest,
                    ),
                  );
                },
              ),
            ),

          // Top controls - Back button and Flash button
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: _goBack,
                  ),
                ),
                // Flash button
                if (_isCameraInitialized &&
                    _cameraController != null &&
                    _cameraController!.value.isInitialized &&
                    _imageFile == null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(_getFlashIcon(),
                          color: Colors.white, size: 24),
                      onPressed: _isProcessing ? null : _toggleFlashMode,
                      tooltip: 'Toggle Flash',
                    ),
                  ),
                // Reset button (when image is captured)
                if (_imageFile != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.refresh, size: 24, color: Colors.white),
                      onPressed: _resetDetection,
                    ),
                  ),
              ],
            ),
          ),

          // Zoom Level Indicator
          if (_isCameraInitialized && _currentZoomLevel > 1.01 && _imageFile == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "${_currentZoomLevel.toStringAsFixed(1)}x",
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + (_imageFile != null ? 120 : 50),
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Gallery button
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.photo_library, size: 24, color: Colors.white),
                      onPressed: (_isProcessing || !_isCameraInitialized) ? null : _pickImageFromGallery,
                    ),
                  ),
                  const SizedBox(width: 50),
                  // Capture button
                  GestureDetector(
                    onTap: (_isProcessing || !_isCameraInitialized || _imageFile != null) ? null : _takePicture,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isProcessing
                            ? const CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 3,
                              )
                            : Container(
                                width: 65,
                                height: 65,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 50),
                  // Flip camera button (only show when camera is active)
                  if (_imageFile == null)
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.flip_camera_ios_outlined, size: 24, color: Colors.white),
                        onPressed: (_isProcessing ||
                                !_isCameraInitialized ||
                                _frontCamera == null ||
                                _backCamera == null)
                            ? null
                            : _flipCamera,
                      ),
                    )
                  else
                    const SizedBox(width: 60), // Placeholder for alignment
                ],
              ),
            ),
          ),

          // Draggable results sheet
          if (_imageFile != null && _showDraggable)
            DraggableScrollableSheet(
              initialChildSize: _initialChildSize,
              minChildSize: _minChildSize,
              maxChildSize: _maxChildSize,
              controller: _dragController,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 15,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Content
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_detectedObjects.isEmpty)
                                Center(
                                  child: Text(
                                    result,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              else ...[
                                Text(
                                  result,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ..._detectedObjects.map((obj) => Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.yellow.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.yellow.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        obj.label,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        "${(obj.confidence * 100).toStringAsFixed(1)}%",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class DetectedObject {
  final Rect boundingBox;
  final String label;
  final double confidence;

  DetectedObject({
    required this.boundingBox,
    required this.label,
    required this.confidence,
  });
}

class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final double scale;
  final Size imageSize;
  final Size canvasSize;

  ObjectDetectorPainter(this.objects, this.scale, this.imageSize, this.canvasSize);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final Paint bgPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.3);

    // Calculate offsets to center the image
    final scaledWidth = imageSize.width * scale;
    final scaledHeight = imageSize.height * scale;
    final offsetX = (canvasSize.width - scaledWidth) / 2;
    final offsetY = (canvasSize.height - scaledHeight) / 2;

    for (final obj in objects) {
      // Scale and offset the bounding box
      final scaledRect = Rect.fromLTRB(
        obj.boundingBox.left * scale + offsetX,
        obj.boundingBox.top * scale + offsetY,
        obj.boundingBox.right * scale + offsetX,
        obj.boundingBox.bottom * scale + offsetY,
      );

      // Draw bounding box
      canvas.drawRect(scaledRect, boxPaint);

      // Draw label background and text
      final textSpan = TextSpan(
        text: "${obj.label} ${(obj.confidence * 100).toStringAsFixed(1)}%",
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final bgRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top - textPainter.height - 8,
        textPainter.width + 12,
        textPainter.height + 8,
      );

      final RRect roundedRect = RRect.fromRectAndRadius(
        bgRect,
        const Radius.circular(6),
      );
      canvas.drawRRect(roundedRect, bgPaint);
      
      textPainter.paint(
        canvas,
        Offset(scaledRect.left + 6, scaledRect.top - textPainter.height - 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}