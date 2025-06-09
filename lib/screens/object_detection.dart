import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:starflut/starflut.dart'; // For Python integration

class ObjectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;
  const ObjectDetection({super.key, required this.cameras});

  @override
  State<ObjectDetection> createState() => _ObjectDetectionState();
}

class _ObjectDetectionState extends State<ObjectDetection>
    with WidgetsBindingObserver {
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
  final ImagePicker _picker = Image.new();

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
    FlashMode.always,
  ];
  int _currentFlashModeIndex = 0;

  // Focus state
  Offset? _focusPoint;
  Timer? _focusPointTimer;

  // Key for the preview container
  final GlobalKey _previewContainerKey = GlobalKey();

  // For draggable sheet
  final DraggableScrollableController _dragController =
      DraggableScrollableController();
  final double _initialChildSize = 0.3;
  final double _minChildSize = 0.3;
  final double _maxChildSize = 0.8;
  bool _showDraggable = false;

  // For Python integration
  Starflut? _starflut;
  bool _isBackendReady = false;

  // CHANGE THIS to localhost to use the integrated Python server
  static const String baseUrl = 'http://127.0.0.1:5000';

  // TTS variables
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  String _detectedLanguage = 'en';
  String _selectedLanguage = 'auto'; // 'auto', 'en', or 'id'
  final Map<String, String> _languageNames = {
    'auto': 'Auto',
    'en': 'English',
    'id': 'Bahasa',
  };

  // Text formatting state variables
  bool _isTextBold = false;
  double _currentFontSize = 15.0;
  static const double _minFontSize = 10.0;
  static const double _maxFontSize = 30.0;
  static const double _fontSizeStep = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initializeTts();
    _initializeApp();
  }

  void _initializeTts() {
    _flutterTts = FlutterTts();

    _flutterTts.setStartHandler(() => setState(() => _isSpeaking = true));
    _flutterTts.setCompletionHandler(() => setState(() => _isSpeaking = false));
    _flutterTts.setCancelHandler(() => setState(() => _isSpeaking = false));
    _flutterTts.setErrorHandler((msg) {
      setState(() => _isSpeaking = false);
      print("TTS Error: $msg");
    });

    _flutterTts.setPitch(1.0);
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setVolume(1.0);
  }

  Future<void> _initializeApp() async {
    // This now starts the local Python server
    await _initializeAndStartPythonServer();

    if (widget.cameras.isNotEmpty) {
      _setupCamerasAndInitialize();
    }
  }

  Future<void> _initializeAndStartPythonServer() async {
    setState(() {
      result = "Initializing Python backend...";
    });

    try {
      // Get the path to the bundled Python script
      final String appPy = await rootBundle.loadString('assets/python/app.py');

      // Initialize Starflut
      _starflut = await Starflut.newStarflut();

      // Get the path for the model in the app's private directory
      // This makes the model file accessible to the Python script
      final String modelPath = await Starflut.getResourcePath("yolo11n.pt");

      // Run the Python script's main function, passing the model path
      // This will start the Flask server in the background
      await _starflut?.run(
        appPy,
        namedArgs: {"model_path": modelPath},
        function: "main",
      );

      // Give the server a moment to start up before checking its health
      await Future.delayed(const Duration(seconds: 5));

      setState(() {
        _isBackendReady = true;
      });

      // After starting, check its health
      await _checkBackendConnection();
    } catch (e) {
      print("Failed to initialize Python backend: $e");
      if (mounted) {
        setState(() {
          result = "Error: Could not start local server.";
        });
      }
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
    if (!_isBackendReady) {
      setState(() => result = "Backend is not ready. Please wait.");
      return;
    }
    try {
      setState(() {
        result = "Connecting to local YOLO backend...";
      });

      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          result = "Tap the button to detect objects";
        });
      } else {
        setState(() {
          result = "Local backend failed. Status: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        result = "Cannot connect to local backend. Retrying...";
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

      _minZoomLevel = await _cameraController!.getMinZoomLevel();
      _maxZoomLevel = await _cameraController!.getMaxZoomLevel();
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
    _flutterTts.stop();
    _starflut?.dispose(); // Dispose starflut instance
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _dragController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
      if (mounted) setState(() => _isCameraInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      if (_currentCamera != null) {
        _initializeCamera(_currentCamera!);
      }
    }
  }

  void _flipCamera() {
    if (_isProcessing || _frontCamera == null || _backCamera == null) return;
    final newCamera =
        (_cameraController!.description.lensDirection ==
                CameraLensDirection.back)
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
      await _cameraController!.setFlashMode(_currentFlashMode);
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

  String _getDetectedObjectsText() {
    if (_detectedObjects.isEmpty) {
      return "No objects detected";
    }
    String text =
        "I detected ${_detectedObjects.length} object${_detectedObjects.length > 1 ? 's' : ''}: ";
    Map<String, int> objectCounts = {};
    for (var obj in _detectedObjects) {
      objectCounts[obj.label] = (objectCounts[obj.label] ?? 0) + 1;
    }
    List<String> objectDescriptions = [];
    objectCounts.forEach((label, count) {
      objectDescriptions.add("$count $label${count > 1 ? 's' : ''}");
    });
    text += objectDescriptions.join(", ");
    return text;
  }

  Future<void> _speakText() async {
    String textToSpeak = _getDetectedObjectsText();
    if (textToSpeak.isEmpty || textToSpeak == "No objects detected") {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No objects to speak')));
      return;
    }
    if (_isSpeaking) {
      await _flutterTts.stop();
    } else {
      String languageToUse =
          _selectedLanguage == 'auto'
              ? _detectedLanguage
              : (_selectedLanguage == 'id' ? 'id-ID' : 'en-US');
      await _flutterTts.setLanguage(languageToUse);
      await _flutterTts.speak(textToSpeak);
    }
  }

  void _showLanguageMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Select Language',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ..._languageNames.entries.map((entry) {
                bool isSelected = _selectedLanguage == entry.key;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : Colors.grey,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? Colors.blue : Colors.black,
                    ),
                  ),
                  subtitle:
                      entry.key == 'auto'
                          ? Text(
                            'Detected: ${_detectedLanguage == 'id' ? 'Bahasa Indonesia' : 'English'}',
                          )
                          : null,
                  onTap: () {
                    setState(() => _selectedLanguage = entry.key);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processImage() async {
    if (_imageFile == null) return;

    setState(() {
      _isProcessing = true;
      result = "Analyzing image...";
      _detectedObjects = [];
      _showDraggable = true;
    });
    if (_isSpeaking) _flutterTts.stop();

    try {
      final decodedImage = await decodeImageFromList(
        await _imageFile!.readAsBytes(),
      );
      _imageSize = Size(
        decodedImage.width.toDouble(),
        decodedImage.height.toDouble(),
      );

      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http
          .post(
            Uri.parse('$baseUrl/detect'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image': base64Image}),
          )
          .timeout(
            const Duration(seconds: 90),
          ); // Increased timeout for on-device processing

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          List<DetectedObject> detectedObjects =
              (data['detections'] as List).map((detection) {
                final bbox = detection['bbox'] as List;
                return DetectedObject(
                  boundingBox: Rect.fromLTRB(
                    bbox[0].toDouble(),
                    bbox[1].toDouble(),
                    bbox[2].toDouble(),
                    bbox[3].toDouble(),
                  ),
                  label: detection['class'],
                  confidence: detection['confidence'].toDouble(),
                );
              }).toList();

          setState(() {
            _detectedObjects = detectedObjects;
            if (detectedObjects.isEmpty) {
              result =
                  "No objects detected. Try a different angle or lighting.";
            } else {
              result = "Found ${detectedObjects.length} object(s)";
              _dragController.animateTo(
                0.5,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        } else {
          setState(() => result = "Detection failed: ${data['error']}");
        }
      } else {
        setState(() => result = "Server error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => result = "Detection failed: $e");
      print("Detection error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _resetDetection() {
    setState(() {
      _imageFile = null;
      _detectedObjects = [];
      result = "Tap the button to detect objects";
      _showDraggable = false;
      _isTextBold = false;
      _currentFontSize = 15.0;
    });
    if (_isSpeaking) _flutterTts.stop();
    _dragController.animateTo(
      _minChildSize,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _increaseFontSize() => setState(
    () =>
        _currentFontSize = (_currentFontSize + _fontSizeStep).clamp(
          _minFontSize,
          _maxFontSize,
        ),
  );
  void _decreaseFontSize() => setState(
    () =>
        _currentFontSize = (_currentFontSize - _fontSizeStep).clamp(
          _minFontSize,
          _maxFontSize,
        ),
  );
  void _toggleBold() => setState(() => _isTextBold = !_isTextBold);

  void _handleScaleStart(ScaleStartDetails details) =>
      _baseZoomLevel = _currentZoomLevel;

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_cameraController == null) return;
    double newZoomLevel = (_baseZoomLevel * details.scale).clamp(
      _minZoomLevel,
      _maxZoomLevel,
    );
    if (newZoomLevel != _currentZoomLevel) {
      await _cameraController!.setZoomLevel(newZoomLevel);
      if (mounted) setState(() => _currentZoomLevel = newZoomLevel);
    }
  }

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
    }
  }

  void _toggleFlashMode() async {
    if (_cameraController == null) return;
    _currentFlashModeIndex = (_currentFlashModeIndex + 1) % _flashModes.length;
    _currentFlashMode = _flashModes[_currentFlashModeIndex];
    try {
      await _cameraController!.setFlashMode(_currentFlashMode);
      if (mounted) setState(() {});
    } catch (e) {
      print("Error setting flash mode: $e");
    }
  }

  Future<void> _handleTapToFocus(TapUpDetails details) async {
    if (_cameraController == null) return;
    final RenderBox? previewBox =
        _previewContainerKey.currentContext?.findRenderObject() as RenderBox?;
    if (previewBox == null || !previewBox.hasSize) return;

    final Offset localOffset = previewBox.globalToLocal(details.globalPosition);
    final Offset tapPoint = Offset(
      (localOffset.dx / previewBox.size.width).clamp(0.0, 1.0),
      (localOffset.dy / previewBox.size.height).clamp(0.0, 1.0),
    );

    try {
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setFocusPoint(tapPoint);

      if (mounted) {
        setState(() => _focusPoint = localOffset);
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
    if (!_isCameraInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              result,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height:
                MediaQuery.of(context).size.width *
                _cameraController!.value.aspectRatio,
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
            child:
                _imageFile != null
                    ? Image.file(_imageFile!, fit: BoxFit.contain)
                    : FutureBuilder<void>(
                      future: _initializeControllerFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done) {
                          return _buildCameraPreview(context);
                        } else {
                          return Center(
                            child: Text(
                              result,
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }
                      },
                    ),
          ),

          // Bounding boxes overlay
          if (_imageFile != null &&
              _detectedObjects.isNotEmpty &&
              _imageSize != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double scale =
                      (constraints.maxWidth / _imageSize!.width <
                              constraints.maxHeight / _imageSize!.height)
                          ? constraints.maxWidth / _imageSize!.width
                          : constraints.maxHeight / _imageSize!.height;
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

          // Top controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                if (_imageFile == null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(_getFlashIcon(), color: Colors.white),
                      onPressed: _isProcessing ? null : _toggleFlashMode,
                    ),
                  ),
                if (_imageFile != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _resetDetection,
                    ),
                  ),
              ],
            ),
          ),

          // Zoom Level Indicator
          if (_isCameraInitialized &&
              _currentZoomLevel > 1.01 &&
              _imageFile == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
            bottom:
                MediaQuery.of(context).padding.bottom +
                (_imageFile != null ? 120 : 50),
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildControlButton(
                    Icons.photo_library,
                    _pickImageFromGallery,
                  ),
                  _buildCaptureButton(),
                  if (_imageFile == null)
                    _buildControlButton(
                      Icons.flip_camera_ios_outlined,
                      _flipCamera,
                    )
                  else
                    const SizedBox(width: 60), // Placeholder for alignment
                ],
              ),
            ),
          ),

          // Draggable results sheet
          if (_showDraggable)
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
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: _buildDraggableContent(),
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

  Widget _buildControlButton(IconData icon, VoidCallback? onPressed) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
      ),
      child: IconButton(
        icon: Icon(icon, size: 24, color: Colors.white),
        onPressed: (_isProcessing || !_isCameraInitialized) ? null : onPressed,
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap:
          (_isProcessing || !_isCameraInitialized || _imageFile != null)
              ? null
              : _takePicture,
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
          child:
              _isProcessing
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
    );
  }

  Widget _buildDraggableContent() {
    if (_isProcessing && _detectedObjects.isEmpty) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 40),
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            "Detecting Objects via Local YOLO...",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: Colors.black54,
            ),
          ),
        ],
      );
    }

    if (_detectedObjects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40.0),
        child: Center(
          child: Text(
            result,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          "Object Detection Result",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SelectableText(
            _getDetectedObjectsText(),
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: _currentFontSize,
              fontWeight: _isTextBold ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Detected Objects",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        ..._detectedObjects.map(
          (obj) => Container(
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
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildTextFormattingControls(),
        const SizedBox(height: 24),
        _buildTtsControls(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTextFormattingControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Text Formatting",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.text_decrease),
              onPressed: _decreaseFontSize,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Text(
                '${_currentFontSize.toStringAsFixed(0)}px',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.text_increase),
              onPressed: _increaseFontSize,
            ),
            IconButton(
              icon: const Icon(Icons.format_bold),
              color: _isTextBold ? Colors.blue : Colors.grey[600],
              onPressed: _toggleBold,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTtsControls() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              onTap: _speakText,
              borderRadius: BorderRadius.circular(40),
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade600],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            InkWell(
              onTap: _showLanguageMenu,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.language, size: 24, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Text(
                      _languageNames[_selectedLanguage]!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 24,
                      color: Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _isSpeaking ? 'Stop Reading' : 'Read Text',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Helper Classes ---

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

  ObjectDetectorPainter(
    this.objects,
    this.scale,
    this.imageSize,
    this.canvasSize,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint =
        Paint()
          ..color = Colors.yellow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;

    final Paint bgPaint = Paint()..color = Colors.yellow.withOpacity(0.8);

    final double offsetX = (canvasSize.width - (imageSize.width * scale)) / 2;
    final double offsetY = (canvasSize.height - (imageSize.height * scale)) / 2;

    for (final obj in objects) {
      final Rect scaledRect = Rect.fromLTRB(
        obj.boundingBox.left * scale + offsetX,
        obj.boundingBox.top * scale + offsetY,
        obj.boundingBox.right * scale + offsetX,
        obj.boundingBox.bottom * scale + offsetY,
      );
      canvas.drawRect(scaledRect, boxPaint);

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
      )..layout();
      final double textHeight = textPainter.height;
      final double textWidth = textPainter.width;

      final Rect bgRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top - textHeight - 8,
        textWidth + 12,
        textHeight + 8,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
        bgPaint,
      );
      textPainter.paint(canvas, Offset(bgRect.left + 6, bgRect.top + 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
