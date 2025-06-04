import 'dart:io'; // Added for Platform
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart'; // Added

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticker Maker Example',
      home: const StickerPage(),
    );
  }
}

class StickerPage extends StatefulWidget {
  const StickerPage({super.key});
  @override
  State<StickerPage> createState() => _StickerPageState();
}

class _StickerPageState extends State<StickerPage> {
  Uint8List? _inputImage;
  Uint8List? _stickerImage;
  bool _addBorder = true;
  String _borderColor = '#FFFFFF';
  double _borderWidth = 12.0;

  Future<bool> _requestPermissions({bool forCamera = false}) async {
    Map<Permission, PermissionStatus> statuses;
    List<Permission> permsToRequest = [Permission.photos];
    if (forCamera) {
      permsToRequest.add(Permission.camera);
    }

    statuses = await permsToRequest.request();

    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!(status.isGranted || (Platform.isIOS && status.isLimited))) {
        allGranted = false;
      }
    });
    return allGranted;
  }

  Future<void> _handlePermanentlyDenied({bool forCamera = false}) async {
    bool photosPermanentlyDenied = await Permission.photos.isPermanentlyDenied;
    bool cameraPermanentlyDenied =
        forCamera ? await Permission.camera.isPermanentlyDenied : false;

    if (photosPermanentlyDenied || (forCamera && cameraPermanentlyDenied)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Permissions are permanently denied. Please enable them in app settings.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () async {
                await openAppSettings();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    final granted = await _requestPermissions(forCamera: false);
    if (!granted) {
      await _handlePermanentlyDenied(forCamera: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo library permission needed to pick images.'),
          ),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final XFile? imageFile = await picker.pickImage(
      source: ImageSource.gallery,
    );
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      setState(() {
        _inputImage = bytes;
        _stickerImage = null;
      });
    }
  }

  Future<void> _captureImageWithCamera() async {
    final granted = await _requestPermissions(forCamera: true);
    if (!granted) {
      await _handlePermanentlyDenied(forCamera: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera and Photo library permissions needed.'),
          ),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final XFile? imageFile = await picker.pickImage(source: ImageSource.camera);
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      setState(() {
        _inputImage = bytes;
        _stickerImage = null;
      });
    }
  }

  Future<void> _createSticker() async {
    if (_inputImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }
    try {
      setState(() {
        _stickerImage = null; // Show loading or clear previous
      });
      final Uint8List? stickerBytes = await FlutterStickerMaker.makeSticker(
        _inputImage!,
        borderColor: _borderColor,
        addBorder: _addBorder,
        borderWidth: _borderWidth,
      );
      setState(() {
        _stickerImage = stickerBytes;
      });
      if (stickerBytes == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create sticker. No result.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create sticker: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[400],
      appBar: AppBar(title: const Text('Sticker Maker Demo')),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Action buttons
              ElevatedButton(
                onPressed: _pickImageFromGallery,
                child: const Text('Pick Image from Gallery'),
              ),
              ElevatedButton(
                onPressed: _captureImageWithCamera,
                child: const Text('Capture Image with Camera'),
              ),
              const SizedBox(height: 20),

              // Border controls
              if (_inputImage != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Add Border:'),
                    Switch(
                      value: _addBorder,
                      onChanged: (value) {
                        setState(() {
                          _addBorder = value;
                        });
                      },
                    ),
                  ],
                ),
                if (_addBorder) ...[
                  const Text('Border Color:'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildColorButton('#FFFFFF', 'White'),
                      _buildColorButton('#FF0000', 'Red'),
                      _buildColorButton('#00FF00', 'Green'),
                      _buildColorButton('#0000FF', 'Blue'),
                      _buildColorButton('#FFFF00', 'Yellow'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        Text('Border Width: ${_borderWidth.round()}'),
                        Slider(
                          value: _borderWidth,
                          min: 2.0,
                          max: 30.0,
                          divisions: 28,
                          onChanged: (value) {
                            setState(() {
                              _borderWidth = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _createSticker,
                  child: const Text('Create Sticker'),
                ),
              ],

              // Responsive image layout
              if (_inputImage != null || _stickerImage != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isLargeScreen = constraints.maxWidth > 600;

                      if (isLargeScreen) {
                        // Horizontal layout for large screens
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_inputImage != null)
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Input Image:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      constraints: const BoxConstraints(
                                        maxHeight: 300,
                                      ),
                                      child: Image.memory(
                                        _inputImage!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_inputImage != null && _stickerImage != null)
                              const SizedBox(width: 20),
                            if (_stickerImage != null)
                              Expanded(
                                child: Column(
                                  children: [
                                    const Text(
                                      'Sticker Result:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      constraints: const BoxConstraints(
                                        maxHeight: 300,
                                      ),
                                      child: Image.memory(
                                        _stickerImage!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      } else {
                        // Vertical layout for small screens
                        return Column(
                          children: [
                            if (_inputImage != null) ...[
                              const Text(
                                'Input Image:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Image.memory(_inputImage!, height: 200),
                              const SizedBox(height: 20),
                            ],
                            if (_stickerImage != null) ...[
                              const Text(
                                'Sticker Result:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Image.memory(_stickerImage!, height: 200),
                            ],
                          ],
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorButton(String color, String label) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _borderColor = color;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Color(int.parse(color.substring(1), radix: 16) + 0xFF000000),
          border: Border.all(
            color: _borderColor == color ? Colors.black : Colors.grey,
            width: _borderColor == color ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                color == '#FFFFFF' || color == '#FFFF00'
                    ? Colors.black
                    : Colors.white,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
