import 'dart:async'; // For Timer
import 'dart:convert'; // Untuk jsonDecode
import 'dart:io'; // Untuk File
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http; // Untuk membuat permintaan HTTP
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'text_detection_page.dart';

// Global cameras list (ensure it's initialized before use)
List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
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
            )),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(elevation: 0),
        ),
      ),
      home: cameras.isNotEmpty
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
      appBar: AppBar(title: const Text("Kesalahan Kamera")),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            "Tidak ada kamera yang terdeteksi di perangkat ini atau akses kamera ditolak. Aplikasi tidak dapat melanjutkan fungsi utama.",
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

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4) // Slightly less opaque grid
      ..strokeWidth = 0.5;

    final double thirdWidth = size.width / 3;
    final double thirdHeight = size.height / 3;

    canvas.drawLine(
        Offset(thirdWidth, 0), Offset(thirdWidth, size.height), paint);
    canvas.drawLine(
        Offset(2 * thirdWidth, 0), Offset(2 * thirdWidth, size.height), paint);
    canvas.drawLine(
        Offset(0, thirdHeight), Offset(size.width, thirdHeight), paint);
    canvas.drawLine(
        Offset(0, 2 * thirdHeight), Offset(size.width, 2 * thirdHeight), paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
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
    FlashMode.always
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
              content: Text('Failed to initialize camera: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusPointTimer?.cancel();
    _controller?.dispose();
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
      final XFile? pickedImage =
          await _picker.pickImage(source: ImageSource.gallery);
      if (pickedImage != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  AcceptDenyPage(imagePath: pickedImage.path)),
        );
      }
    } catch (e) {
      print("Error opening gallery: $e");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open gallery: ${e.toString()}')));
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
            builder: (context) => AcceptDenyPage(imagePath: image.path)),
      );
    } catch (e) {
      print('Error taking picture: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to take picture: ${e.toString()}')));
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
    double newZoomLevel =
        (_baseZoomLevel * details.scale).clamp(_minZoomLevel, _maxZoomLevel);
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
      // Optionally, set exposure point too if desired
      // await _controller!.setExposureMode(ExposureMode.auto);
      // await _controller!.setExposurePoint(tapPoint);

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
      return const Center(child: CircularProgressIndicator());
    }

    double cameraAspectRatio = _controller!.value.aspectRatio;
    if (cameraAspectRatio > 1) cameraAspectRatio = 1.0 / cameraAspectRatio;

    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          key: _previewContainerKey, // Assign key here
          aspectRatio: cameraAspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                // For pinch-to-zoom and tap-to-focus
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onTapUp: _handleTapToFocus,
                child: CameraPreview(_controller!),
              ),
              CustomPaint(painter: GridPainter()),
              if (_focusPoint != null) // Visual focus indicator
                Positioned(
                  left: _focusPoint!.dx - 30, // Adjust size/position as needed
                  top: _focusPoint!.dy - 30,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.yellow, width: 2),
                      shape: BoxShape.rectangle, // Or CircleShape
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cameras.isEmpty) return const NoCameraPage();

    return Scaffold(
      backgroundColor: Colors.black, // Make background black for immersive feel
      body: SafeArea(
        // Ensure UI respects notches and system areas
        child: Stack(
          children: [
            // Camera Preview
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
                                textAlign: TextAlign.center)));
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),

            // Top Controls (Flash)
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween, // Align flash to one side
                  children: [
                    Container(
                      // Placeholder for other potential top-left controls
                      width: 48, height: 48,
                    ),
                    if (_isCameraInitialized &&
                        _controller != null &&
                        _controller!.value.isInitialized)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(_getFlashIcon(),
                              color: Colors.white, size: 28),
                          onPressed: _isProcessing ? null : _toggleFlashMode,
                          tooltip: 'Toggle Flash',
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Zoom Level Indicator (Optional)
            if (_isCameraInitialized &&
                _currentZoomLevel > 1.01) // Show only if zoomed
              Positioned(
                top: 70, // Adjust position as needed
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

            // Bottom Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 120 +
                    MediaQuery.of(context).padding.bottom, // Adjusted height
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom > 0
                        ? MediaQuery.of(context).padding.bottom
                        : 20,
                    top: 20),
                color: Colors.black.withOpacity(
                    0.0), // Make transparent to blend with black scaffold
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.photo_library_outlined,
                          size: 32, color: Colors.white),
                      onPressed: (_isProcessing || !_isCameraInitialized)
                          ? null
                          : _openGallery,
                      tooltip: 'Open Gallery',
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: (_isProcessing || !_isCameraInitialized)
                            ? null
                            : _takePicture,
                        customBorder: const CircleBorder(),
                        splashColor: Colors.white.withOpacity(0.5),
                        highlightColor: Colors.white.withOpacity(0.3),
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 3), // Lighter border
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2))
                              ]),
                          child: (_isProcessing &&
                                  (_controller?.value.isTakingPicture ?? false))
                              ? const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child:
                                      CircularProgressIndicator(strokeWidth: 3))
                              : null,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios_outlined,
                          size: 32, color: Colors.white),
                      onPressed: (_isProcessing ||
                              !_isCameraInitialized ||
                              _frontCamera == null ||
                              _backCamera == null)
                          ? null
                          : _flipCamera,
                      tooltip: 'Flip Camera',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

// This is the class we are modifying
class _AcceptDenyPageState extends State<AcceptDenyPage> {
  String _ocrResult = 'Processing...';
  bool _isLoading = true;

  // Existing state variables for text formatting
  bool _isTextBold = false;
  double _currentFontSize = 15.0;
  static const double _minFontSize = 10.0;
  static const double _maxFontSize = 30.0;
  static const double _fontSizeStep = 1.0;

  final String _googleApiKey =
      "AIzaSyCZYjhnCmIZ53Z6zIzNTHEPz-AVO8R7He4"; // [ Already in your code ]

  // New state variables for smooth dragging
  double? _currentTextPaneHeight; // Current height of the text pane
  final double _initialTextPaneProportion =
      0.4; // Text pane will initially take 40% of available vertical space
  final double _minPanePixelHeight =
      80.0; // Minimum height for both image and text panes
  final double _draggableHandleHeight = 24.0; // Height of the drag handle

  @override
  void initState() {
    super.initState();
    // Call the new OCR processing method
    _processImageWithGoogleVision(widget.imagePath);
  }

  void _increaseFontSize() {
    setState(() {
      _currentFontSize =
          (_currentFontSize + _fontSizeStep).clamp(_minFontSize, _maxFontSize);
    });
  }

  void _decreaseFontSize() {
    setState(() {
      _currentFontSize =
          (_currentFontSize - _fontSizeStep).clamp(_minFontSize, _maxFontSize);
    });
  }

  void _toggleBold() {
    setState(() {
      _isTextBold = !_isTextBold;
    });
  }

  void _handleVerticalDragSmooth(
      DragUpdateDetails details, double totalHeightForTextAndImagePanes) {
    if (_currentTextPaneHeight == null) return; // Should be initialized by now
    setState(() {
      // If finger drags handle DOWN (details.delta.dy > 0), text pane (below handle) should SHRINK.
      // If finger drags handle UP (details.delta.dy < 0), text pane (below handle) should EXPAND.
      // So, we subtract details.delta.dy from the current text pane's height.
      double newTextPaneHeight =
          _currentTextPaneHeight! - details.delta.dy; // Changed from + to -

      // Clamping logic remains the same: ensures neither pane goes below _minPanePixelHeight
      _currentTextPaneHeight = newTextPaneHeight.clamp(_minPanePixelHeight,
          totalHeightForTextAndImagePanes - _minPanePixelHeight);
    });
  }

  Future<void> _processImageWithGoogleVision(String imagePath) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _ocrResult = "Preparing image and contacting Google Vision API...";
    });

    if (_googleApiKey == "YOUR_GOOGLE_CLOUD_VISION_API_KEY" ||
        _googleApiKey.isEmpty) {
      if (mounted) {
        setState(() {
          _ocrResult =
              "ERROR: Google Cloud Vision API Key is not set in the code. Please replace the placeholder API key in _AcceptDenyPageState.";
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
      // 1. Read image file
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
      Uint8List imageBytes = await imageFile.readAsBytes();

      // 2. Preprocess image using the 'image' package
      // This mimics parts of your Python preprocessing: grayscale and median blur.
      // Adaptive thresholding is more complex and not directly available in the 'image' package.
      img.Image? originalImage = img.decodeImage(imageBytes);
      String base64Image;

      if (originalImage != null) {
        print("Preprocessing image: Grayscale and Median Blur...");
        img.Image grayscaleImage = img.grayscale(originalImage);
        // Median filter with radius 1 is a 3x3 kernel, similar to cv2.medianBlur(img, 3)
        img.Image denoisedImage = img.gaussianBlur(grayscaleImage, radius: 1);

        // Encode back to PNG (lossless, good after processing) or JPEG
        List<int> processedImageBytes =
            img.encodePng(denoisedImage); // Or img.encodeJpg for smaller size
        base64Image = base64Encode(processedImageBytes);
        print("Preprocessing complete. Image encoded to base64.");
      } else {
        // Fallback to original bytes if decoding failed (should not happen for valid images from picker/camera)
        print(
            "Warning: Could not decode image for preprocessing. Using original image bytes.");
        base64Image = base64Encode(imageBytes);
      }

      // 3. Construct Google Vision API request payload
      String visionApiUrl =
          'https://vision.googleapis.com/v1/images:annotate?key=$_googleApiKey';
      Map<String, dynamic> requestPayload = {
        'requests': [
          {
            'image': {'content': base64Image},
            'features': [
              {'type': 'TEXT_DETECTION'}
            ],
            // Optional: Add language hints if your Python model used them
            // 'imageContext': {'languageHints': ['en', 'id']}
          }
        ]
      };

      print("Sending request to Google Vision API...");
      // 4. Make HTTP POST request
      final response = await http
          .post(
            Uri.parse(visionApiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestPayload),
          )
          .timeout(const Duration(seconds: 60)); // Increased timeout slightly

      print(
          "Received response from Google Vision API. Status: ${response.statusCode}");

      // 5. Parse response and update UI
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
              // The first textAnnotation is the full detected text block.
              _ocrResult =
                  firstResponse['textAnnotations'][0]['description']?.trim() ??
                      "No text description found.";
              if (_ocrResult.isEmpty)
                _ocrResult = "No text detected in image (empty description).";
            } else {
              _ocrResult = "No text detected in image (no textAnnotations).";
            }
          } else {
            // This case might indicate an issue with the API key or request structure if no 'responses' array is present.
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
    // Approximate height of the formatting controls row.
    // For more precision, you could use a GlobalKey and get its size after layout.
    const double formattingControlsApproxHeight = 70.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Text Recognition Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double totalScaffoldBodyHeight = constraints.maxHeight;

          // Calculate the height available for the image, handle, and text panes
          final double heightAvailableForResizableContent =
              totalScaffoldBodyHeight -
                  formattingControlsApproxHeight - // Subtract height of formatting controls
                  _draggableHandleHeight - // Subtract height of the drag handle
                  (MediaQuery.of(context).padding.bottom > 0
                      ? 0
                      : 8.0); // Adjust for bottom padding/notch

          // Initialize _currentTextPaneHeight on the first build or if layout changes
          if (_currentTextPaneHeight == null ||
              (_currentTextPaneHeight! > heightAvailableForResizableContent)) {
            _currentTextPaneHeight =
                heightAvailableForResizableContent * _initialTextPaneProportion;
          }

          // Clamp the text pane's height based on available space and minimums
          _currentTextPaneHeight = _currentTextPaneHeight!.clamp(
              _minPanePixelHeight,
              heightAvailableForResizableContent -
                  _minPanePixelHeight // Max height ensuring image pane also has min height
              );

          double actualTextPaneHeight = _currentTextPaneHeight!;
          double actualImagePaneHeight =
              heightAvailableForResizableContent - actualTextPaneHeight;

          // Ensure image pane height is also at least minimum (could happen if total space is very small)
          if (actualImagePaneHeight < _minPanePixelHeight) {
            actualImagePaneHeight = _minPanePixelHeight;
            // If we adjusted image height, re-calculate text height if possible, or accept overlap if space too small
            if (heightAvailableForResizableContent - actualImagePaneHeight >=
                _minPanePixelHeight) {
              actualTextPaneHeight =
                  heightAvailableForResizableContent - actualImagePaneHeight;
              _currentTextPaneHeight =
                  actualTextPaneHeight; // Update state if changed
            } else {
              // This case means total space is not enough for two min height panes + handle.
              // One or both might appear smaller than _minPanePixelHeight.
              // For simplicity, we prioritize text pane's calculated height if image had to be adjusted.
              actualTextPaneHeight =
                  heightAvailableForResizableContent - actualImagePaneHeight;
              _currentTextPaneHeight = actualTextPaneHeight.clamp(
                  _minPanePixelHeight, double.infinity);
            }
          }

          return Column(
            children: [
              // Image Area
              SizedBox(
                height: actualImagePaneHeight.isNegative
                    ? 0
                    : actualImagePaneHeight,
                child: Container(
                  color: Colors.grey[200],
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12.0),
                  child: Image.file(
                    File(widget.imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                          child: Text("Failed to load image preview.",
                              style: TextStyle(color: Colors.red)));
                    },
                  ),
                ),
              ),

              // Draggable Handle
              GestureDetector(
                onVerticalDragUpdate: (details) => _handleVerticalDragSmooth(
                    details, heightAvailableForResizableContent),
                child: Container(
                  height: _draggableHandleHeight,
                  color:
                      Theme.of(context).colorScheme.secondary.withOpacity(0.4),
                  child: const Center(
                    child: Icon(
                      Icons.drag_handle,
                      size: 22.0,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),

              // Text Result Area
              SizedBox(
                height:
                    actualTextPaneHeight.isNegative ? 0 : actualTextPaneHeight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        // Use Expanded here so the Container fills the SizedBox
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: _isLoading
                              ? const Center(
                                  child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text("Detecting Text via Google Vision...",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ))
                              : SingleChildScrollView(
                                  child: SelectableText(
                                    _ocrResult,
                                    textAlign: TextAlign.left,
                                    style: TextStyle(
                                      fontSize: _currentFontSize,
                                      fontWeight: _isTextBold
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Text Formatting Controls (Their height is accounted for by formattingControlsApproxHeight)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      iconSize: 28,
                      onPressed: _decreaseFontSize,
                      tooltip: 'Decrease font size',
                    ),
                    Text(
                      '${_currentFontSize.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      iconSize: 28,
                      onPressed: _increaseFontSize,
                      tooltip: 'Increase font size',
                    ),
                    IconButton(
                      icon: const Icon(Icons.format_bold),
                      iconSize: 28,
                      color: _isTextBold
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[600],
                      onPressed: _toggleBold,
                      tooltip: 'Toggle Bold',
                    ),
                  ],
                ),
              ),
              SizedBox(
                  height: MediaQuery.of(context).padding.bottom > 0 ? 0 : 8.0)
            ],
          );
        },
      ),
    );
  }
}
