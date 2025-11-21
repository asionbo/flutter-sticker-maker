## 0.2.0
* Refactored visual effect animation.
* Added `VisualEffectBuilder` for custom overlay implementations.

## 0.1.9
* Enhanced ONNX processing by utilizing pixel image handling and mask generation.
* Improved the overlay effect animation.

## 0.1.8
* Added visual effect feature with `showVisualEffect` parameter. Flutter overlay on ONNX platforms (Android & older iOS). Native SwiftUI overlay on iOS 17+.
* Shows animated overlay with blur effect and mask highlighting during processing.
* Uses SwiftUI and iOS Vision API for smooth animations.

## 0.1.7
* Minimal iOS version raised to 16.0. Minimal Android SDK raised to 24.
* Support 16 KB page sizes for Android X64 devices.
* Fixed image orientation issues on iOS after background removal.

## 0.1.6
* Improved performance for mask processing on iOS and Android.

## 0.1.5
* Fix caching mechanism for processed masks and images.

## 0.1.4
* Updated Android target SDK version to 35.
  
## 0.1.3
* Enhanced background removal for Android and iOS using ONNX models.
* Added resource management method.
  
## 0.1.2
* Background removal for Android and the iOS below iOS 17.0 using ONNX models.
* Add compatibility for iOS 15.5+.

## 0.1.1
* Fixed issues with background removal on iOS.
* Improved performance for background removal on Android.

## 0.1.0

* Initial release of flutter_sticker_maker.
* Background removal for iOS using Vision/CoreImage.
* Background removal for Android using MLKit Selfie Segmentation.
* Border support with customizable color and width.