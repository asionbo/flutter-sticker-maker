import Flutter
import UIKit
import Vision
import CoreImage.CIFilterBuiltins

public class FlutterStickerMakerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_sticker_maker", binaryMessenger: registrar.messenger())
    let instance = FlutterStickerMakerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "makeSticker",
       let args = call.arguments as? [String: Any],
       let imageData = args["image"] as? FlutterStandardTypedData,
       let uiImage = UIImage(data: imageData.data) {
      
      let addBorder = args["addBorder"] as? Bool ?? false
      let borderColor = parseBorderColor(args["borderColor"] as? String)
      let borderWidth = CGFloat(args["borderWidth"] as? Double ?? 20.0)
      
      makeSticker(from: uiImage, addBorder: addBorder, borderColor: borderColor, borderWidth: borderWidth) { sticker in
        if let sticker = sticker, let stickerData = sticker.pngData() {
          result(FlutterStandardTypedData(bytes: stickerData))
        } else {
          result(nil)
        }
      }
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  private func makeSticker(from image: UIImage, addBorder: Bool, borderColor: CIColor, borderWidth: CGFloat, completion: @escaping (UIImage?) -> Void) {
    guard let inputCIImage = CIImage(image: image) else {
      completion(nil)
      return
    }
    let handler = VNImageRequestHandler(ciImage: inputCIImage)
    let request = VNGenerateForegroundInstanceMaskRequest()
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try handler.perform([request])
        guard let result = request.results?.first else {
          completion(nil)
          return
        }
        let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        let stickerCIImage = self.apply(maskImage: maskCIImage, to: inputCIImage, addBorder: addBorder, borderColor: borderColor, borderWidth: borderWidth)
        let context = CIContext()
        if let cgImage = context.createCGImage(stickerCIImage, from: stickerCIImage.extent) {
          let stickerImage = UIImage(cgImage: cgImage)
          completion(stickerImage)
        } else {
          completion(nil)
        }
      } catch {
        completion(nil)
      }
    }
  }

  private func apply(maskImage: CIImage, to inputImage: CIImage, addBorder: Bool, borderColor: CIColor, borderWidth: CGFloat) -> CIImage {
    let filter = CIFilter.blendWithMask()
    filter.inputImage = inputImage
    filter.maskImage = maskImage
    filter.backgroundImage = CIImage.empty()
    guard let maskedImage = filter.outputImage else {
      return inputImage
    }
    
    if addBorder {
      return addSimpleWhiteBorder(to: maskedImage, maskImage: maskImage, borderColor: borderColor, borderWidth: borderWidth)
    } else {
      return maskedImage
    }
  }
  
  private func addSimpleWhiteBorder(to image: CIImage, maskImage: CIImage, borderColor: CIColor, borderWidth: CGFloat) -> CIImage {
    // Step 1: Dilate the mask to create border area
    let morphologyFilter = CIFilter.morphologyMaximum()
    morphologyFilter.inputImage = maskImage
    morphologyFilter.radius = Float(borderWidth) // Fix: Convert CGFloat to Float
    
    guard let expandedMask = morphologyFilter.outputImage else {
      return image
    }
    
    // Step 2: Create colored background using the expanded mask
    guard let colorGenerator = CIFilter(name: "CIConstantColorGenerator") else {
      return image
    }
    colorGenerator.setValue(borderColor, forKey: kCIInputColorKey)
    guard let colorImage = colorGenerator.outputImage?.cropped(to: expandedMask.extent) else {
      return image
    }
    
    // Step 3: Apply expanded mask to colored background to create border
    let borderFilter = CIFilter.blendWithMask()
    borderFilter.inputImage = colorImage
    borderFilter.maskImage = expandedMask
    borderFilter.backgroundImage = CIImage.empty()
    
    guard let coloredBorder = borderFilter.outputImage else {
      return image
    }
    
    // Step 4: Composite original masked image over the colored border
    let compositeFilter = CIFilter.sourceOverCompositing()
    compositeFilter.inputImage = image
    compositeFilter.backgroundImage = coloredBorder
    
    return compositeFilter.outputImage ?? image
  }
  
  private func parseBorderColor(_ colorString: String?) -> CIColor {
    guard let colorString = colorString else {
      return CIColor.white
    }
    
    // Parse hex color string (e.g., "#FFFFFF" or "FFFFFF")
    let hex = colorString.hasPrefix("#") ? String(colorString.dropFirst()) : colorString
    
    guard hex.count == 6,
          let hexValue = UInt64(hex, radix: 16) else {
      return CIColor.white
    }
    
    let red = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(hexValue & 0x0000FF) / 255.0
    
    return CIColor(red: red, green: green, blue: blue)
  }
}