# Flutter Sticker Maker

A cross-platform Flutter plugin to create stickers by removing backgrounds from images using iOS Vision/CoreImage and Android MLKit.

## Features

- iOS: Uses Vision and CoreImage for background removal.
- Android: Uses Google ML Kit Selfie Segmentation.
- Handles storage, gallery, and camera permissions automatically.
- Simple Dart API.

## Usage

```dart
import 'package:flutter_sticker_maker/flutter_sticker_maker.dart';

// Pick an image, then:
final sticker = await FlutterStickerMaker.makeSticker(imageBytes);
```

See `example/` for a full demo app.

## Setup

- iOS: Minimum iOS 17.0
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