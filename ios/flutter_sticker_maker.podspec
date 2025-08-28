
Pod::Spec.new do |s|
  s.name             = 'flutter_sticker_maker'
  s.version          = '0.1.0' # Match this with your plugin's pubspec.yaml version
  s.summary          = 'Flutter plugin to create stickers from images using iOS Vision/CoreImage and Android MLKit.' # From your plugin's pubspec.yaml
  s.description      = <<-DESC
Flutter plugin to create stickers from images using iOS Vision/CoreImage and Android MLKit.
                       DESC
  s.homepage         = 'https://your.plugin.homepage.com' # Replace with your plugin's homepage
  s.license          = { :file => '../LICENSE' } # Ensure you have a LICENSE file at the root of your plugin
  s.author           = { 'Asionbo' => 'asionbo@126.com' } # Replace with your details
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/mask_processor.h', 'Classes/simd_optimizations.h'
  s.dependency 'Flutter'
  s.platform = :ios, '15.5' # Updated to support iOS 15.5+ with ONNX for pre-17.0 versions

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_CFLAGS' => '-DUSE_ACCELERATE_FRAMEWORK'
  }
  s.swift_version = '5.0'
  
  # Add Accelerate framework for performance optimizations
  s.frameworks = 'Accelerate'
end