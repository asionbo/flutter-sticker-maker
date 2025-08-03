# Flutter Sticker Maker

A cross-platform Flutter plugin to create stickers by removing backgrounds from images using iOS Vision/CoreImage and Android MLKit.

## Features

- **High-quality detection**: Advanced ML models with preprocessing for better accuracy
- **Adaptive iOS Support**: Vision API for iOS 17+, CoreImage fallback for iOS 15.5-16.x
- iOS: Uses Vision and CoreImage with enhanced quality settings and edge smoothing
- Android: Uses Google ML Kit Selfie Segmentation with image preprocessing and mask smoothing
- Configurable border support with customizable color and width
- Simple Dart API

## Quality Enhancements

- **Image preprocessing**: Automatic contrast and brightness enhancement
- **Edge smoothing**: Advanced algorithms to create natural-looking edges
- **Noise reduction**: Built-in filtering for cleaner results
- **High-resolution support**: Optimized for images up to 4K resolution

## Usage

```dart
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';

// Basic usage
final sticker = await FlutterStickerMaker.makeSticker(imageBytes);

// With border customization
final stickerWithBorder = await FlutterStickerMaker.makeSticker(
  imageBytes,
  addBorder: true,
  borderColor: '#FF0000', // Red border
  borderWidth: 15.0,      // 15 pixel border width
);
```

### Parameters

- `imageBytes`: The input image as Uint8List (PNG/JPEG)
- `addBorder`: Whether to add a border around the sticker (default: true)
- `borderColor`: Hex color string for the border (default: '#FFFFFF')
- `borderWidth`: Width of the border in pixels (default: 12.0)

## Examples

### Demo App Screenshots

![example](example/assets/images/IMG_0121.PNG)


See `example/` for a full demo app.

## Setup

- iOS: Minimum iOS 15.5+ (uses Vision API for iOS 17+, CoreImage fallback for 15.5-16.x)
- Android: Minimum SDK 21

### Permissions

Add to AndroidManifest.xml:
```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
<uses-permission android:name="android.permission.CAMERA" />
```

Add to ios/Runner/Info.plist:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>This app needs access to your photo library to pick images and save stickers.</string>
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to take pictures for sticker creation.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app saves stickers to your photo library.</string>
```