import 'dart:async'; // For Timer
import 'dart:convert'; // Untuk jsonDecode
import 'dart:io'; // Untuk File
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http; // Untuk membuat permintaan HTTP
import 'package:image/image.dart' as img;
import 'package:flutter_tts/flutter_tts.dart'; // Add this import for TTS

// Global cameras list (ensure it's initialized before use)
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error fetching cameras: ${e.code} - ${e.description}');
  }
  runApp(TextDetectionApp(cameras: cameras));
}

class TextDetectionApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const TextDetectionApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Text Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xAAA4C4F4)),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xAAA4C4F4),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(elevation: 0),
        ),
      ),
      home:
          cameras.isNotEmpty
              ? CameraPage(cameras: cameras)
              : const NoCameraPage(),
    );
  }
}

class NoCameraPage extends StatelessWidget {
  const NoCameraPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Camera Error")),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            "No camera detected...",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.redAccent),
          ),
        ),
      ),
    );
  }
}

class CameraPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraPage({super.key, required this.cameras});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;

  CameraDescription? _currentCamera;
  CameraDescription? _frontCamera;
  CameraDescription? _backCamera;

  final ImagePicker _picker = ImagePicker();

  // Zoom state
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _baseZoomLevel = 1.0; // For pinch gesture calculation

  // Flash state
  FlashMode _currentFlashMode = FlashMode.off;
  final List<FlashMode> _flashModes = [
    FlashMode.off,
    FlashMode.auto,
    FlashMode.always,
  ]; // 'always' for ON
  int _currentFlashModeIndex = 0;

  // Focus state
  Offset? _focusPoint; // To visually show focus point (optional)
  Timer? _focusPointTimer; // To hide focus point indicator

  // Key for the preview container to get its size for focus tap
  final GlobalKey _previewContainerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hide system UI for full screen experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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

  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_controller != null) {
      await _controller!.dispose();
    }
    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    if (mounted) setState(() => _isCameraInitialized = false);
    _currentZoomLevel = 1.0; // Reset zoom on camera switch

    _initializeControllerFuture = _controller!.initialize();

    try {
      await _initializeControllerFuture;
      if (!mounted) return;

      // Fetch zoom levels after initialization
      _minZoomLevel = await _controller!.getMinZoomLevel();
      _maxZoomLevel = await _controller!.getMaxZoomLevel();

      // Set initial flash mode (already _currentFlashMode)
      await _controller!.setFlashMode(_currentFlashMode);

      setState(() {
        _isCameraInitialized = true;
        _currentCamera = cameraDescription;
      });
    } catch (e) {
      print('Error initializing camera: $e');
      if (!mounted) return;
      setState(() => _isCameraInitialized = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize camera: ${e.toString()}'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusPointTimer?.cancel();
    _controller?.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
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
        (_controller!.description.lensDirection == CameraLensDirection.back)
            ? _frontCamera!
            : _backCamera!;
    _initializeCamera(newCamera);
  }

  Future<void> _openGallery() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final XFile? pickedImage = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedImage != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AcceptDenyPage(imagePath: pickedImage.path),
          ),
        );
      }
    } catch (e) {
      print("Error opening gallery: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open gallery: ${e.toString()}')),
        );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isProcessing ||
        _controller!.value.isTakingPicture) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      // Ensure flash mode is set
      await _controller!.setFlashMode(_currentFlashMode);
      // Ensure zoom level is set
      await _controller!.setZoomLevel(_currentZoomLevel);

      final XFile image = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AcceptDenyPage(imagePath: image.path),
        ),
      );
    } catch (e) {
      print('Error taking picture: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to take picture: ${e.toString()}')),
        );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- Zoom ---
  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoomLevel = _currentZoomLevel;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    double newZoomLevel = (_baseZoomLevel * details.scale).clamp(
      _minZoomLevel,
      _maxZoomLevel,
    );
    if (newZoomLevel != _currentZoomLevel) {
      await _controller!.setZoomLevel(newZoomLevel);
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
        return Icons.flash_on; // 'always' is effectively 'on'
      case FlashMode.torch:
        return Icons.highlight; // Different icon if torch used
      default:
        return Icons.flash_off;
    }
  }

  void _toggleFlashMode() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _currentFlashModeIndex = (_currentFlashModeIndex + 1) % _flashModes.length;
    _currentFlashMode = _flashModes[_currentFlashModeIndex];
    try {
      await _controller!.setFlashMode(_currentFlashMode);
      if (mounted) setState(() {});
      print("Flash mode set to: $_currentFlashMode");
    } catch (e) {
      print("Error setting flash mode: $e");
    }
  }

  // --- Focus ---
  Future<void> _handleTapToFocus(TapUpDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final RenderBox? previewBox =
        _previewContainerKey.currentContext?.findRenderObject() as RenderBox?;
    if (previewBox == null || !previewBox.hasSize) return;

    final Offset localOffset = previewBox.globalToLocal(details.globalPosition);

    // Normalize offset to 0.0 - 1.0 range
    final double x = (localOffset.dx / previewBox.size.width).clamp(0.0, 1.0);
    final double y = (localOffset.dy / previewBox.size.height).clamp(0.0, 1.0);
    final Offset tapPoint = Offset(x, y);

    try {
      // Set focus mode to auto before setting point, then set point
      await _controller!.setFocusMode(FocusMode.auto);
      await _controller!.setFocusPoint(tapPoint);

      print("Focus point set to: $tapPoint");

      // Visual feedback for focus (optional, can be expanded)
      if (mounted) {
        setState(() {
          _focusPoint =
              localOffset; // Use localOffset for positioning UI element
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
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
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
                _controller!.value.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: _previewContainerKey,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapUp: _handleTapToFocus,
                  child: CameraPreview(_controller!),
                ),
                if (_focusPoint != null) // Visual focus indicator
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
    // Restore system UI before going back
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cameras.isEmpty) return const NoCameraPage();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen camera preview
          Positioned.fill(
            child: FutureBuilder<void>(
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
                    _controller != null &&
                    _controller!.value.isInitialized)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _getFlashIcon(),
                        color: Colors.white,
                        size: 24,
                      ),
                      onPressed: _isProcessing ? null : _toggleFlashMode,
                      tooltip: 'Toggle Flash',
                    ),
                  ),
              ],
            ),
          ),

          // Zoom Level Indicator
          if (_isCameraInitialized && _currentZoomLevel > 1.01)
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
            bottom: MediaQuery.of(context).padding.bottom + 50,
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
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.photo_library,
                        size: 24,
                        color: Colors.white,
                      ),
                      onPressed:
                          (_isProcessing || !_isCameraInitialized)
                              ? null
                              : _openGallery,
                    ),
                  ),
                  const SizedBox(width: 50),
                  // Capture button
                  GestureDetector(
                    onTap:
                        (_isProcessing || !_isCameraInitialized)
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
                  ),
                  const SizedBox(width: 50),
                  // Flip camera button
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.flip_camera_ios_outlined,
                        size: 24,
                        color: Colors.white,
                      ),
                      onPressed:
                          (_isProcessing ||
                                  !_isCameraInitialized ||
                                  _frontCamera == null ||
                                  _backCamera == null)
                              ? null
                              : _flipCamera,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AcceptDenyPage extends StatefulWidget {
  final String imagePath;
  const AcceptDenyPage({super.key, required this.imagePath});

  @override
  State<AcceptDenyPage> createState() => _AcceptDenyPageState();
}

class _AcceptDenyPageState extends State<AcceptDenyPage> {
  String _ocrResult = 'Processing...';
  bool _isLoading = true;
  File? _imageFile;
  Size? _imageSize;

  // Text formatting state variables
  bool _isTextBold = false;
  double _currentFontSize = 15.0;
  static const double _minFontSize = 10.0;
  static const double _maxFontSize = 30.0;
  static const double _fontSizeStep = 1.0;

  // Draggable sheet state
  DraggableScrollableController _dragController =
      DraggableScrollableController();
  double _initialChildSize = 0.4;
  double _minChildSize = 0.1;
  double _maxChildSize = 1.0;
  bool _showDraggable = false;

  final String _googleApiKey = "AIzaSyCZYjhnCmIZ53Z6zIzNTHEPz-AVO8R7He4";

  // TTS variables
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  String _detectedLanguage = 'en';
  String _selectedLanguage = 'auto'; // 'auto', 'en', or 'id'
  Map<String, String> _languageNames = {
    'auto': 'Auto',
    'en': 'English',
    'id': 'Bahasa',
  };

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _imageFile = File(widget.imagePath);
    _initializeTts();
    _processImageWithGoogleVision(widget.imagePath);
  }

  void _initializeTts() {
    _flutterTts = FlutterTts();

    // Configure TTS
    _flutterTts.setStartHandler(() {
      setState(() {
        _isSpeaking = true;
      });
    });

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });

    _flutterTts.setCancelHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });

    _flutterTts.setErrorHandler((msg) {
      setState(() {
        _isSpeaking = false;
      });
      print("TTS Error: $msg");
    });

    // Set default properties
    _flutterTts.setPitch(1.0);
    _flutterTts.setSpeechRate(0.5);
    _flutterTts.setVolume(1.0);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _dragController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  void _increaseFontSize() {
    setState(() {
      _currentFontSize = (_currentFontSize + _fontSizeStep).clamp(
        _minFontSize,
        _maxFontSize,
      );
    });
  }

  void _decreaseFontSize() {
    setState(() {
      _currentFontSize = (_currentFontSize - _fontSizeStep).clamp(
        _minFontSize,
        _maxFontSize,
      );
    });
  }

  void _toggleBold() {
    setState(() {
      _isTextBold = !_isTextBold;
    });
  }

  void _goBack() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  void _resetDetection() {
    setState(() {
      _imageFile = null;
      _ocrResult = 'Processing...';
      _isLoading = true;
      _showDraggable = false;
      _isSpeaking = false;
    });
    _flutterTts.stop();
    _dragController.animateTo(
      _minChildSize,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _speakText() async {
    if (_ocrResult.isEmpty ||
        _ocrResult == 'Processing...' ||
        _ocrResult.startsWith('Error') ||
        _ocrResult.startsWith('ERROR') ||
        _ocrResult.contains('No text detected')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid text to speak'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isSpeaking) {
      await _flutterTts.stop();
      setState(() {
        _isSpeaking = false;
      });
    } else {
      // Determine which language to use
      String languageToUse =
          _selectedLanguage == 'auto'
              ? _detectedLanguage
              : (_selectedLanguage == 'id' ? 'id-ID' : 'en-US');

      // Set language based on user selection or detected language
      await _flutterTts.setLanguage(languageToUse);

      // Speak the text
      var result = await _flutterTts.speak(_ocrResult);
      if (result == 1) {
        setState(() {
          _isSpeaking = true;
        });
      }
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
                            style: const TextStyle(fontSize: 12),
                          )
                          : null,
                  onTap: () {
                    setState(() {
                      _selectedLanguage = entry.key;
                    });
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

  Future<void> _processImageWithGoogleVision(String imagePath) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _ocrResult = "Detecting text...";
      _showDraggable = true;
    });

    if (_googleApiKey == "YOUR_GOOGLE_CLOUD_VISION_API_KEY" ||
        _googleApiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _ocrResult =
              "ERROR: Google Cloud Vision API Key is not set in the code.";
          _isLoading = false;
        });
      }
      return;
    }

    if (imagePath.isEmpty) {
      if (mounted) {
        setState(() {
          _ocrResult = "Image path is invalid or empty.";
          _isLoading = false;
        });
      }
      return;
    }

    try {
      // Get image dimensions
      final imageBytes = await File(imagePath).readAsBytes();
      final decodedImage = await decodeImageFromList(imageBytes);
      _imageSize = Size(
        decodedImage.width.toDouble(),
        decodedImage.height.toDouble(),
      );

      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        if (mounted) {
          setState(() {
            _ocrResult = "Error: Image file not found at path: $imagePath";
            _isLoading = false;
          });
        }
        return;
      }

      Uint8List imageFileBytes = await imageFile.readAsBytes();
      String base64Image;

      img.Image? originalImage = img.decodeImage(imageFileBytes);

      if (originalImage != null) {
        print("Preprocessing image: Grayscale and Median Blur...");
        img.Image grayscaleImage = img.grayscale(originalImage);
        img.Image denoisedImage = img.gaussianBlur(grayscaleImage, radius: 1);

        List<int> processedImageBytes = img.encodePng(denoisedImage);
        base64Image = base64Encode(processedImageBytes);
        print("Preprocessing complete. Image encoded to base64.");
      } else {
        print(
          "Warning: Could not decode image for preprocessing. Using original image bytes.",
        );
        base64Image = base64Encode(imageFileBytes);
      }

      String visionApiUrl =
          'https://vision.googleapis.com/v1/images:annotate?key=$_googleApiKey';
      Map<String, dynamic> requestPayload = {
        'requests': [
          {
            'image': {'content': base64Image},
            'features': [
              {'type': 'TEXT_DETECTION'},
            ],
          },
        ],
      };

      print("Sending request to Google Vision API...");
      final response = await http
          .post(
            Uri.parse(visionApiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestPayload),
          )
          .timeout(const Duration(seconds: 60));

      print(
        "Received response from Google Vision API. Status: ${response.statusCode}",
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        if (response.statusCode == 200) {
          var decodedResponse = jsonDecode(response.body);

          if (decodedResponse['responses'] != null &&
              decodedResponse['responses'].isNotEmpty) {
            var firstResponse = decodedResponse['responses'][0];
            if (firstResponse['error'] != null &&
                firstResponse['error']['message'] != null) {
              _ocrResult =
                  "Google API Error: ${firstResponse['error']['message']}";
            } else if (firstResponse['textAnnotations'] != null &&
                firstResponse['textAnnotations'].isNotEmpty) {
              _ocrResult =
                  firstResponse['textAnnotations'][0]['description']?.trim() ??
                  "No text description found.";

              // Get detected language
              _detectedLanguage =
                  firstResponse['textAnnotations'][0]['locale'] ?? 'en';

              if (_ocrResult.isEmpty)
                _ocrResult = "No text detected in image (empty description).";

              // Expand the sheet when text is detected
              _dragController.animateTo(
                0.5,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            } else {
              _ocrResult = "No text detected in image (no textAnnotations).";
            }
          } else {
            _ocrResult =
                "Invalid response structure from Google API. Raw: ${response.body.substring(0, (response.body.length > 200 ? 200 : response.body.length))}";
          }
        } else {
          _ocrResult =
              "Error calling Google API: HTTP ${response.statusCode}\nResponse: ${response.body.substring(0, (response.body.length > 300 ? 300 : response.body.length))}";
        }
      });
    } on TimeoutException catch (e) {
      print("Timeout Error: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _ocrResult =
            "Request to Google Vision API timed out. Please check your internet connection and try again.";
      });
    } on SocketException catch (e) {
      print("Socket/Network Error: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _ocrResult =
            "Network error: Could not connect to Google Vision API. Please check your internet connection.";
      });
    } catch (e) {
      print("Unexpected Error in _processImageWithGoogleVision: $e");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _ocrResult = "An unexpected error occurred: ${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen image
          Positioned.fill(
            child:
                _imageFile != null
                    ? AspectRatio(
                      aspectRatio:
                          _imageSize != null
                              ? _imageSize!.width / _imageSize!.height
                              : 1.0,
                      child: Image.file(_imageFile!, fit: BoxFit.contain),
                    )
                    : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
          ),

          // Top controls - Back button
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
                // Reset button
                if (_imageFile != null)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        size: 24,
                        color: Colors.white,
                      ),
                      onPressed: _resetDetection,
                    ),
                  ),
              ],
            ),
          ),

          // Draggable results sheet - Only show when processing or text detected
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
                              // Title
                              const Text(
                                "Text Recognition Result",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Text result container
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child:
                                    _isLoading
                                        ? const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            CircularProgressIndicator(),
                                            SizedBox(height: 16),
                                            Text(
                                              "Detecting Text via Google Vision...",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontStyle: FontStyle.italic,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        )
                                        : SelectableText(
                                          _ocrResult,
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                            fontSize: _currentFontSize,
                                            fontWeight:
                                                _isTextBold
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                            color: Colors.black87,
                                          ),
                                        ),
                              ),

                              const SizedBox(height: 20),

                              // Text formatting controls
                              if (!_isLoading) ...[
                                const Text(
                                  "Text Formatting",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    // Decrease font size
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.text_decrease),
                                        iconSize: 24,
                                        onPressed: _decreaseFontSize,
                                        tooltip: 'Decrease font size',
                                      ),
                                    ),
                                    // Font size indicator
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.blue.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        '${_currentFontSize.toStringAsFixed(0)}px',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    // Increase font size
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.text_increase),
                                        iconSize: 24,
                                        onPressed: _increaseFontSize,
                                        tooltip: 'Increase font size',
                                      ),
                                    ),
                                    // Bold toggle
                                    Container(
                                      decoration: BoxDecoration(
                                        color:
                                            _isTextBold
                                                ? Colors.blue.withOpacity(0.2)
                                                : Colors.grey.shade200,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.format_bold),
                                        iconSize: 24,
                                        color:
                                            _isTextBold
                                                ? Colors.blue
                                                : Colors.grey[600],
                                        onPressed: _toggleBold,
                                        tooltip: 'Toggle Bold',
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 24),

                                // Text-to-Speech controls
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // TTS button
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.blue.shade400,
                                            Colors.blue.shade600,
                                          ],
                                        ),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue.withOpacity(0.3),
                                            blurRadius: 15,
                                            spreadRadius: 2,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _speakText,
                                          borderRadius: BorderRadius.circular(
                                            40,
                                          ),
                                          child: Center(
                                            child: Icon(
                                              _isSpeaking
                                                  ? Icons.stop_rounded
                                                  : Icons.volume_up_rounded,
                                              size: 29,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    // Language selector button
                                    Container(
                                      height: 50,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(30),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                          width: 1,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: _showLanguageMenu,
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.language,
                                                size: 24,
                                                color: Colors.grey[700],
                                              ),
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
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Center(
                                  child: Text(
                                    _isSpeaking ? 'Stop Reading' : 'Read Text',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ],

                              // Add some bottom padding
                              const SizedBox(height: 20),
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
