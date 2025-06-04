
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
  s.dependency 'Flutter'
  s.platform = :ios, '17.0' # The Vision API VNGenerateForegroundInstanceMaskRequest requires iOS 15.0+

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end