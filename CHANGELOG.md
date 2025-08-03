## 0.1.2
* Added iOS 15.5+ compatibility support.
* iOS 17+: Uses Vision API for high-quality foreground segmentation.
* iOS 15.5-16.x: Uses CoreImage fallback for basic subject isolation.
* Updated minimum iOS version from 17.0 to 15.5.

## 0.1.1
* Fixed issues with background removal on iOS.
* Improved performance for background removal on Android.

## 0.1.0

* Initial release of flutter_sticker_maker.
* Background removal for iOS using Vision/CoreImage.
* Background removal for Android using MLKit Selfie Segmentation.
* Border support with customizable color and width.