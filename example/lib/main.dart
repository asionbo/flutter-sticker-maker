import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sticker_maker/permissions_util.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const StickerPage());
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

  Future<void> _pickImageWithPermissions() async {
    final granted = await PermissionsUtil.requestAll();
    if (!granted) {
      await PermissionsUtil.handlePermanentlyDenied();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permissions needed to pick or save images.')),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _inputImage = bytes);
    }
  }

  Future<void> _makeSticker() async {
    if (_inputImage == null) return;
    final sticker = await FlutterStickerMaker.makeSticker(_inputImage!);
    setState(() => _stickerImage = sticker);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sticker Maker')),
      body: Column(
        children: [
          if (_inputImage != null)
            Image.memory(_inputImage!, height: 200),
          if (_stickerImage != null)
            Image.memory(_stickerImage!, height: 200),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(onPressed: _pickImageWithPermissions, child: const Text('Pick Image')),
              const SizedBox(width: 16),
              ElevatedButton(onPressed: _makeSticker, child: const Text('Make Sticker')),
            ],
          ),
        ],
      ),
    );
  }
}