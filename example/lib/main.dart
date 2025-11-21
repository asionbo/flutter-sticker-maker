import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:example/services/permission_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sticker Maker Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatelessWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sticker Maker Example')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const StickerPage()),
            );
          },
          child: const Text('Go to Sticker Maker'),
        ),
      ),
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
  bool _addBorder = StickerDefaults.defaultAddBorder;
  String _borderColor = StickerDefaults.defaultBorderColor;
  double _borderWidth = StickerDefaults.defaultBorderWidth;
  bool _showVisualEffect = StickerDefaults.defaultShowVisualEffect;
  SpeckleType _speckleType = SpeckleType.classic;
  bool _useCustomVisualEffect = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    FlutterStickerMaker.initialize();
  }

  @override
  void dispose() {
    _inputImage = null;
    _stickerImage = null;
    FlutterStickerMaker.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final granted = await PermissionService.requestImagePermissions();
      if (!granted) {
        await _handlePermissionDenied();
        return;
      }

      final picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );

      if (imageFile != null) {
        final bytes = await imageFile.readAsBytes();
        setState(() {
          _inputImage = bytes;
          _stickerImage = null;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<void> _captureImageWithCamera() async {
    try {
      final granted = await PermissionService.requestImagePermissions(
        includeCamera: true,
      );
      if (!granted) {
        await _handlePermissionDenied(includeCamera: true);
        return;
      }

      final picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );

      if (imageFile != null) {
        final bytes = await imageFile.readAsBytes();
        setState(() {
          _inputImage = bytes;
          _stickerImage = null;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to capture image: $e');
    }
  }

  Future<void> _handlePermissionDenied({bool includeCamera = false}) async {
    final permanentlyDenied =
        await PermissionService.arePermissionsPermanentlyDenied(
          includeCamera: includeCamera,
        );

    if (permanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Permissions are permanently denied. Please enable them in app settings.',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => PermissionService.openSettings(),
          ),
        ),
      );
    } else if (mounted) {
      final message =
          includeCamera
              ? 'Camera and photo library permissions are needed.'
              : 'Photo library permission is needed to pick images.';
      _showErrorSnackBar(message);
    }
  }

  Future<void> _createSticker() async {
    if (_inputImage == null) {
      _showErrorSnackBar('Please select an image first.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _stickerImage = null;
    });

    try {
      final stickerBytes = await FlutterStickerMaker.makeSticker(
        _inputImage!,
        addBorder: _addBorder,
        borderColor: _borderColor,
        borderWidth: _borderWidth,
        showVisualEffect: _showVisualEffect && !_useCustomVisualEffect,
        speckleType: _speckleType,
        visualEffectBuilder:
            _showVisualEffect && _useCustomVisualEffect
                ? _customVisualEffectBuilder
                : null,
      );

      setState(() {
        _stickerImage = stickerBytes;
        _isProcessing = false;
      });

      if (stickerBytes == null && mounted) {
        _showErrorSnackBar('Failed to create sticker. No result returned.');
      }
    } on StickerException catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showErrorSnackBar('Sticker creation failed: ${e.message}');
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      _showErrorSnackBar('Unexpected error: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('Sticker Maker Demo'), elevation: 2),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildActionButtons(),
            if (_inputImage != null) ...[
              const SizedBox(height: 24),
              _buildBorderControls(),
              const SizedBox(height: 16),
              _buildCreateStickerButton(),
            ],
            if (_inputImage != null || _stickerImage != null) ...[
              const SizedBox(height: 24),
              _buildImageDisplay(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Select an Image',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _captureImageWithCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBorderControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sticker Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Show Visual Effect'),
              subtitle: const Text(
                'iOS 17+ native or Flutter overlay on ONNX platforms',
              ),
              value: _showVisualEffect,
              onChanged: (value) {
                setState(() {
                  _showVisualEffect = value;
                  if (!value) {
                    _useCustomVisualEffect = false;
                  }
                });
              },
            ),
            if (_showVisualEffect) ...[
              const SizedBox(height: 8),
              const Text(
                'Overlay Type',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Default overlay'),
                    selected: !_useCustomVisualEffect,
                    onSelected: (_) {
                      setState(() {
                        _useCustomVisualEffect = false;
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Custom builder'),
                    selected: _useCustomVisualEffect,
                    onSelected: (_) {
                      setState(() {
                        _useCustomVisualEffect = true;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (!_useCustomVisualEffect) ...[
                const SizedBox(height: 16),
                const Text(
                  'Speckle Style',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      SpeckleType.values.map((type) {
                        final isSelected = _speckleType == type;
                        return ChoiceChip(
                          label: Text(_describeSpeckle(type)),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _speckleType = type;
                            });
                          },
                        );
                      }).toList(),
                ),
              ],
            ],
            const Divider(),
            SwitchListTile(
              title: const Text('Add Border'),
              value: _addBorder,
              onChanged: (value) {
                setState(() {
                  _addBorder = value;
                });
              },
            ),
            if (_addBorder) ...[
              const SizedBox(height: 16),
              const Text('Border Color:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildColorButton('#FFFFFF', 'White'),
                  _buildColorButton('#FF0000', 'Red'),
                  _buildColorButton('#00FF00', 'Green'),
                  _buildColorButton('#0000FF', 'Blue'),
                  _buildColorButton('#FFFF00', 'Yellow'),
                  _buildColorButton('#FF00FF', 'Magenta'),
                ],
              ),
              const SizedBox(height: 16),
              Text('Border Width: ${_borderWidth.round()}px'),
              Slider(
                value: _borderWidth,
                min: StickerDefaults.minBorderWidth,
                max: StickerDefaults.maxBorderWidth,
                divisions: 50,
                onChanged: (value) {
                  setState(() {
                    _borderWidth = value;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreateStickerButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isProcessing ? null : _createSticker,
        icon:
            _isProcessing
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.auto_fix_high, color: Colors.white),
        label: Text(_isProcessing ? 'Creating Sticker...' : 'Create Sticker'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildImageDisplay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth > 600;

        if (isLargeScreen && _inputImage != null && _stickerImage != null) {
          return _buildHorizontalImageLayout();
        } else {
          return _buildVerticalImageLayout();
        }
      },
    );
  }

  Widget _buildHorizontalImageLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_inputImage != null)
          Expanded(child: _buildImageCard('Original Image', _inputImage!)),
        if (_inputImage != null && _stickerImage != null)
          const SizedBox(width: 16),
        if (_stickerImage != null)
          Expanded(child: _buildImageCard('Sticker Result', _stickerImage!)),
      ],
    );
  }

  Widget _buildVerticalImageLayout() {
    return Column(
      children: [
        if (_inputImage != null) ...[
          _buildImageCard('Original Image', _inputImage!),
          const SizedBox(height: 16),
        ],
        if (_stickerImage != null)
          _buildImageCard('Sticker Result', _stickerImage!),
      ],
    );
  }

  Widget _buildImageCard(String title, Uint8List imageBytes) {
    return Card(
      color: Colors.grey[400],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorButton(String color, String label) {
    final isSelected = _borderColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          _borderColor = color;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Color(int.parse(color.substring(1), radix: 16) + 0xFF000000),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.grey,
            width: isSelected ? 3 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                ['#FFFFFF', '#FFFF00'].contains(color)
                    ? Colors.black
                    : Colors.white,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _describeSpeckle(SpeckleType type) => type.label;

  VisualEffectBuilder get _customVisualEffectBuilder => (
    BuildContext context,
    VisualEffectRequest request,
  ) {
    /// Keep the overlay visible until dismissed manually.
    request.keepOverlayUntilDismissed();

    /// Create a memory image from the original bytes.
    final memoryImage = Image.memory(
      request.imageBytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.20),
                BlendMode.srcOver,
              ),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: memoryImage,
              ),
            ),
          ),

          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.95, end: 1.0),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder:
                  (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
              child: FutureBuilder<Uint8List?>(
                future: request.processing,
                builder: (context, snapshot) {
                  final completed =
                      snapshot.connectionState == ConnectionState.done;

                  /// Show the processed image if available.
                  final resultBytes = snapshot.data;

                  /// Auto dismiss the overlay after a short delay.
                  if (completed) {
                    Future<void>.delayed(
                      const Duration(milliseconds: 500),
                    ).then((_) => request.dismiss());
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child:
                            completed && resultBytes != null
                                ? ClipRRect(
                                  key: const ValueKey('preview'),
                                  child: Image.memory(
                                    resultBytes,
                                    fit: BoxFit.contain,
                                  ),
                                )
                                : Column(
                                  key: const ValueKey('progress'),
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 4,
                                        valueColor: AlwaysStoppedAnimation(
                                          Colors.white,
                                        ),
                                      ),
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
          Align(
            alignment: Alignment.bottomCenter,
            child: TextButton.icon(
              onPressed: request.dismiss,
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text('Hide overlay'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  };
}
