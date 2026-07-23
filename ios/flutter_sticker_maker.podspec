
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
  s.source_files = 'flutter_sticker_maker/Sources/flutter_sticker_maker/**/*.swift', 'flutter_sticker_maker/Sources/flutter_sticker_maker_c/**/*.{c,m,h}'
  s.public_header_files = 'flutter_sticker_maker/Sources/flutter_sticker_maker_c/include/flutter_sticker_maker_c/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0' # Updated to support iOS 16.0+ with ONNX for pre-17.0 versions

  s.resources = ['flutter_sticker_maker/Sources/*.png']

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_CFLAGS' => '-DUSE_ACCELERATE_FRAMEWORK'
  }
  s.swift_version = '5.0'
  
  # Add Accelerate framework for performance optimizations
  s.frameworks = 'Accelerate'

  s.static_framework = true 
end