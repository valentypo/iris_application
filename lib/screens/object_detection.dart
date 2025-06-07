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

class _ObjectDetectionState extends State<ObjectDetection> {
  late CameraController _cameraController;
  bool isCameraReady = false;
  String result = "Initializing...";
  bool isDetecting = false;
  File? _imageFile;
  List<DetectedObject> _detectedObjects = [];
  Size? _imageSize;
  final ImagePicker _picker = ImagePicker();
  
  // For draggable sheet
  DraggableScrollableController _dragController = DraggableScrollableController();
  double _initialChildSize = 0.3;
  double _minChildSize = 0.1;
  double _maxChildSize = 1.0;

  // Change this to your computer's IP address when testing on physical device
  static const String baseUrl = 'http://172.20.10.5:5000';
  bool _showDraggable = false;

  @override
  void initState() {
    super.initState();
    // Hide system UI for full screen experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkBackendConnection();
    await _initializeCamera();
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

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() {
        result = "No cameras available";
      });
      return;
    }

    try {
      _cameraController = CameraController(
        widget.cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController.initialize();

      if (!mounted) return;
      
      setState(() {
        isCameraReady = true;
        result = "Tap the button to detect objects";
      });
    } catch (e) {
      setState(() {
        result = "Camera initialization failed: $e";
      });
      print("Camera error: $e");
    }
  }

  Future<void> _pickImageFromGallery() async {
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
    }
  }

  Future<void> _takePicture() async {
    if (!isCameraReady || isDetecting) {
      return;
    }

    try {
      final XFile picture = await _cameraController.takePicture();
      _imageFile = File(picture.path);
      await _processImage();
    } catch (e) {
      setState(() {
        result = "Failed to take picture: $e";
      });
    }
  }

  Future<void> _processImage() async {
    if (_imageFile == null) return;

    setState(() {
      isDetecting = true;
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
        isDetecting = false;
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

  void _goBack() {
    // Restore system UI before going back
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (isCameraReady) {
      _cameraController.dispose();
    }
    _dragController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full screen camera preview or image
          Positioned.fill(
            child: isCameraReady
                ? (_imageFile != null
                    ? AspectRatio(
                        aspectRatio: _imageSize != null 
                            ? _imageSize!.width / _imageSize!.height 
                            : 1.0,
                        child: Image.file(
                          _imageFile!,
                          fit: BoxFit.contain,
                        ),
                      )
                    : ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.width * _cameraController.value.aspectRatio,
                              child: CameraPreview(_cameraController),
                            ),
                          ),
                        ),
                      ))
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
          ),

          // Bounding boxes overlay - Now visible with yellow color
          if (_imageFile != null && _detectedObjects.isNotEmpty && _imageSize != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // For captured images, use proper aspect ratio scaling
                  final imageAspectRatio = _imageSize!.width / _imageSize!.height;
                  final screenAspectRatio = constraints.maxWidth / constraints.maxHeight;
                  
                  double scale;
                  double offsetX = 0;
                  double offsetY = 0;
                  
                  if (imageAspectRatio > screenAspectRatio) {
                    // Image is wider than screen
                    scale = constraints.maxWidth / _imageSize!.width;
                    final scaledHeight = _imageSize!.height * scale;
                    offsetY = (constraints.maxHeight - scaledHeight) / 2;
                  } else {
                    // Image is taller than screen
                    scale = constraints.maxHeight / _imageSize!.height;
                    final scaledWidth = _imageSize!.width * scale;
                    offsetX = (constraints.maxWidth - scaledWidth) / 2;
                  }
                  
                  return CustomPaint(
                    painter: ObjectDetectorPainter(
                      _detectedObjects,
                      scale,
                      _imageSize!,
                      constraints.biggest,
                      offsetX,
                      offsetY,
                    ),
                  );
                },
              ),
            ),

          // Top controls - Back button and status
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
                // Status text for camera mode
                if (_imageFile == null && result.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      result,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
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
                      onPressed: _pickImageFromGallery,
                    ),
                  ),
                  const SizedBox(width: 50),
                  // Capture button
                  GestureDetector(
                    onTap: (isCameraReady && !isDetecting) ? _takePicture : null,
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
                        child: isDetecting
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
                  // Reset button (appears after detection)
                  if (_imageFile != null)
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh, size: 24, color: Colors.white),
                        onPressed: _resetDetection,
                      ),
                    )
                  else
                    const SizedBox(width: 60), // Placeholder for alignment
                ],
              ),
            ),
          ),

          // Draggable results sheet - Only show when _imageFile is not null
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
  final double offsetX;
  final double offsetY;

  ObjectDetectorPainter(this.objects, this.scale, this.imageSize, this.canvasSize, this.offsetX, this.offsetY);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint = Paint()
      ..color = Colors.yellow // Changed to visible yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final Paint bgPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.3); // Semi-transparent yellow background

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