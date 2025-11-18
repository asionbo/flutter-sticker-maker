import CoreImage.CIFilterBuiltins
import Flutter
import UIKit
import Vision
import os.log
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Configuration
private struct StickerMakerConfig {
  static let defaultBorderWidth: CGFloat = 20.0
  static let defaultNoiseLevel: Float = 0.02
  static let defaultSharpness: Float = 0.4
  static let defaultContrast: Float = 1.1
  static let defaultBrightness: Float = 0.05
  static let defaultSaturation: Float = 1.05
  static let maskBlurRadius: Float = 1.0
  static let channelName = "flutter_sticker_maker"
}

// MARK: - Error Types
internal enum StickerMakerError: Error, LocalizedError {
  case invalidImageData
  case imagePreprocessingFailed
  case maskGenerationFailed
  case imageRenderingFailed
  case unsupportedImageFormat

  var errorDescription: String? {
    switch self {
    case .invalidImageData: return "Invalid image data provided"
    case .imagePreprocessingFailed: return "Failed to preprocess image"
    case .maskGenerationFailed: return "Failed to generate foreground mask"
    case .imageRenderingFailed: return "Failed to render final image"
    case .unsupportedImageFormat: return "Unsupported image format"
    }
  }
}

// MARK: - Main Plugin Class
public class FlutterStickerMakerPlugin: NSObject, FlutterPlugin {
  private let logger = OSLog(
    subsystem: Bundle.main.bundleIdentifier ?? "StickerMaker", category: "Plugin")
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
  private let imageProcessor = ImageProcessor()
  private let borderRenderer = BorderRenderer()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: StickerMakerConfig.channelName, binaryMessenger: registrar.messenger())
    let instance = FlutterStickerMakerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "makeSticker":
      // Only handle sticker creation for iOS 17+
      if #available(iOS 17.0, *) {
        do {
          let parameters = try validateAndParseArguments(call.arguments)
          processSticker(with: parameters, result: result)
        } catch {
          os_log(
            "Parameter validation failed: %@", log: logger, type: .error, error.localizedDescription
          )
          result(
            FlutterError(
              code: "INVALID_ARGUMENTS", message: error.localizedDescription, details: nil))
        }
      } else {
        // For iOS < 17.0, delegate to Dart ONNX implementation
        result(
          FlutterError(
            code: "UNSUPPORTED_VERSION",
            message: "iOS version < 17.0 should use ONNX implementation", details: nil))
      }
    case "getIOSVersion":
      let version = UIDevice.current.systemVersion
      result(version)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func validateAndParseArguments(_ arguments: Any?) throws -> StickerParameters {
    guard let args = arguments as? [String: Any],
      let imageData = args["image"] as? FlutterStandardTypedData,
      let uiImage = UIImage(data: imageData.data)
    else {
      throw StickerMakerError.invalidImageData
    }

    let addBorder = args["addBorder"] as? Bool ?? false
    let borderColor = ColorParser.parse(args["borderColor"] as? String)
    let borderWidth = CGFloat(
      args["borderWidth"] as? Double ?? StickerMakerConfig.defaultBorderWidth)
    let showVisualEffect = args["showVisualEffect"] as? Bool ?? false

    return StickerParameters(
      image: uiImage,
      addBorder: addBorder,
      borderColor: borderColor,
      borderWidth: max(0, borderWidth),  // Ensure non-negative
      showVisualEffect: showVisualEffect
    )
  }

  private func processSticker(with parameters: StickerParameters, result: @escaping FlutterResult) {
    // Check if visual effect should be shown (iOS 18+ only)
    if #available(iOS 17.0, *), parameters.showVisualEffect {
      // Use main thread for UI presentation
      DispatchQueue.main.async { [weak self] in
        guard let self = self else {
          result(
            FlutterError(
              code: "INTERNAL_ERROR", message: "Plugin instance deallocated", details: nil))
          return
        }
        
        self.processStickerWithVisualEffect(with: parameters, result: result)
      }
    } else {
      // Process without visual effect
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else {
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "INTERNAL_ERROR", message: "Plugin instance deallocated", details: nil))
          }
          return
        }

        do {
          let stickerImage = try self.createSticker(from: parameters)
          guard let stickerData = stickerImage.pngData() else {
            throw StickerMakerError.imageRenderingFailed
          }

          DispatchQueue.main.async {
            result(FlutterStandardTypedData(bytes: stickerData))
          }
        } catch {
          os_log(
            "Sticker creation failed: %@", log: self.logger, type: .error, error.localizedDescription)
          DispatchQueue.main.async {
            result(
              FlutterError(
                code: "PROCESSING_ERROR", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  @available(iOS 17.0, *)
  private func processStickerWithVisualEffect(
    with parameters: StickerParameters,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "INTERNAL_ERROR", message: "Plugin instance deallocated", details: nil))
        }
        return
      }

      do {
        let preprocessedImage = try self.imageProcessor.preprocess(parameters.image)

        self.presentStickerAnimation(
          originalImage: preprocessedImage,
          parameters: parameters,
          result: result
        )
      } catch {
        os_log(
          "Sticker creation failed: %@", log: self.logger, type: .error, error.localizedDescription)
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "PROCESSING_ERROR", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func createSticker(from parameters: StickerParameters) throws -> UIImage {
    let preprocessedImage = try imageProcessor.preprocess(parameters.image)
    let maskImage: CIImage
    if #available(iOS 17.0, *) {
      maskImage = try generateMask(for: preprocessedImage)
    } else {
      throw StickerMakerError.maskGenerationFailed
    }
    let finalCIImage = try buildFinalImage(
      parameters: parameters,
      preprocessedImage: preprocessedImage,
      maskImage: maskImage)
    return try renderImage(finalCIImage, originalImage: parameters.image)
  }

  private func buildFinalImage(
    parameters: StickerParameters,
    preprocessedImage: UIImage,
    maskImage: CIImage
  ) throws -> CIImage {
    let maskedImage = try buildMaskedImage(
      preprocessedImage: preprocessedImage,
      maskImage: maskImage)
    return addBorderIfNeeded(to: maskedImage, mask: maskImage, parameters: parameters)
  }

  internal func buildMaskedImage(
    preprocessedImage: UIImage,
    maskImage: CIImage
  ) throws -> CIImage {
    let ciImage = CIImage(image: preprocessedImage) ?? CIImage()
    let orientedCIImage = ciImage.oriented(
      forExifOrientation: Int32(preprocessedImage.imageOrientation.exifOrientation))
    return try applyMask(maskImage, to: orientedCIImage)
  }

  internal func addBorderIfNeeded(
    to image: CIImage,
    mask: CIImage,
    parameters: StickerParameters
  ) -> CIImage {
    guard parameters.addBorder else { return image }
    return borderRenderer.addBorder(
      to: image,
      mask: mask,
      color: parameters.borderColor,
      width: parameters.borderWidth)
  }

  @available(iOS 17.0, *)
  internal func generateMask(for image: UIImage) throws -> CIImage {
    let maskGenerator = MaskGenerator()
    return try maskGenerator.generateMask(for: image)
  }

  internal func renderImage(_ ciImage: CIImage, originalImage: UIImage) throws -> UIImage {
    guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
      throw StickerMakerError.imageRenderingFailed
    }
    return UIImage(cgImage: cgImage, scale: 1.0, orientation: originalImage.imageOrientation)
  }

  private func applyMask(_ maskImage: CIImage, to inputImage: CIImage) throws -> CIImage {
    let filter = CIFilter.blendWithMask()
    filter.inputImage = inputImage
    filter.maskImage = maskImage
    filter.backgroundImage = CIImage.empty()

    guard let result = filter.outputImage else {
      throw StickerMakerError.maskGenerationFailed
    }
    return result
  }

  internal func uiImage(
    from ciImage: CIImage,
    scale: CGFloat = UIScreen.main.scale,
    orientation: UIImage.Orientation = .up
  ) throws -> UIImage {
    guard let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
      throw StickerMakerError.imageRenderingFailed
    }
    return UIImage(cgImage: cg, scale: scale, orientation: orientation)
  }

  @available(iOS 17.0, *)
  private func presentStickerAnimation(
    originalImage: UIImage,
    parameters: StickerParameters,
    result: @escaping FlutterResult
  ) {
#if canImport(SwiftUI)
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result(
          FlutterError(
            code: "INTERNAL_ERROR", message: "Plugin instance deallocated", details: nil))
        return
      }

      guard
        let windowScene = UIApplication.shared.connectedScenes
          .compactMap({ $0 as? UIWindowScene })
          .first(where: { $0.activationState == .foregroundActive })
          ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
        let presentingWindow = windowScene.windows.first(where: { $0.isKeyWindow })
          ?? windowScene.windows.first,
        let rootViewController = presentingWindow.rootViewController
      else {
        result(
          FlutterError(
            code: "INTERNAL_ERROR", message: "Failed to find window", details: nil))
        return
      }

      let hostingController = UIHostingController(
        rootView: StickerAnimateView(
          originalImage: originalImage,
          parameters: parameters,
          plugin: self,
          onComplete: { [weak rootViewController] stickerData in
            rootViewController?.presentedViewController?.dismiss(animated: false) {
              result(FlutterStandardTypedData(bytes: stickerData))
            }
          },
          onError: { [weak rootViewController] error in
            rootViewController?.presentedViewController?.dismiss(animated: false) {
              result(
                FlutterError(
                  code: "PROCESSING_ERROR", message: error.localizedDescription, details: nil))
            }
          }
        ))
      hostingController.view.backgroundColor = UIColor.clear
      hostingController.modalPresentationStyle = .overFullScreen

      rootViewController.present(hostingController, animated: false)
    }
#else
    result(
      FlutterError(
        code: "UNSUPPORTED", message: "SwiftUI not available", details: nil))
#endif
  }
}

// MARK: - Supporting Types
internal struct StickerParameters {
  let image: UIImage
  let addBorder: Bool
  let borderColor: CIColor
  let borderWidth: CGFloat
  let showVisualEffect: Bool
}

// MARK: - Image Processor
private class ImageProcessor {
  private let context = CIContext(options: [.useSoftwareRenderer: false, .priorityRequestLow: true])
  
  func preprocess(_ image: UIImage) throws -> UIImage {
    guard let cgImage = image.cgImage else {
      throw StickerMakerError.unsupportedImageFormat
    }

    let ciImage = CIImage(cgImage: cgImage)

    // Apply noise reduction
    let noiseFilter = CIFilter.noiseReduction()
    noiseFilter.inputImage = ciImage
    noiseFilter.noiseLevel = StickerMakerConfig.defaultNoiseLevel
    noiseFilter.sharpness = StickerMakerConfig.defaultSharpness

    // Apply contrast enhancement
    let contrastFilter = CIFilter.colorControls()
    contrastFilter.inputImage = noiseFilter.outputImage
    contrastFilter.contrast = StickerMakerConfig.defaultContrast
    contrastFilter.brightness = StickerMakerConfig.defaultBrightness
    contrastFilter.saturation = StickerMakerConfig.defaultSaturation

    guard let outputImage = contrastFilter.outputImage,
      let processedCGImage = context.createCGImage(outputImage, from: outputImage.extent)
    else {
      throw StickerMakerError.imagePreprocessingFailed
    }

      return UIImage(cgImage: processedCGImage, scale: image.scale, orientation: image.imageOrientation)
  }
}

// MARK: - Mask Generator
@available(iOS 17.0, *)
private class MaskGenerator {
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
  
  func generateMask(for image: UIImage) throws -> CIImage {
    guard let inputCIImage = CIImage(image: image) else {
      throw StickerMakerError.invalidImageData
    }

    let handler = VNImageRequestHandler(
      ciImage: inputCIImage,
      options: [
        VNImageOption.cameraIntrinsics: NSNull(),
        VNImageOption.ciContext: ciContext,
      ])

    let request = VNGenerateForegroundInstanceMaskRequest()
    request.revision = VNGenerateForegroundInstanceMaskRequestRevision1
    request.preferBackgroundProcessing = true

    try handler.perform([request])

    guard let result = request.results?.first else {
      throw StickerMakerError.maskGenerationFailed
    }

    let maskPixelBuffer: CVPixelBuffer
    do {
      maskPixelBuffer = try result.generateScaledMaskForImage(
        forInstances: result.allInstances, from: handler)
    } catch {
      // If generateScaledMaskForImage fails, throw the mask generation error
      throw StickerMakerError.maskGenerationFailed
    }

    let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
    let smoothedMask = smoothMaskEdges(maskCIImage)
          
    // Apply the same orientation transform to the mask as the original image
    let orientedMask = smoothedMask.oriented(forExifOrientation: Int32(image.imageOrientation.exifOrientation))
          
    return orientedMask
  }

  private func smoothMaskEdges(_ maskImage: CIImage) -> CIImage {
    let blurFilter = CIFilter.gaussianBlur()
    blurFilter.inputImage = maskImage
    blurFilter.radius = StickerMakerConfig.maskBlurRadius
    return blurFilter.outputImage ?? maskImage
  }
}

// MARK: - Border Renderer
private class BorderRenderer {
  func addBorder(to image: CIImage, mask: CIImage, color: CIColor, width: CGFloat) -> CIImage {
    guard width > 0 else { return image }

    // Create expanded mask for border
    let morphologyFilter = CIFilter.morphologyMaximum()
    morphologyFilter.inputImage = mask
    morphologyFilter.radius = Float(width)

    guard let expandedMask = morphologyFilter.outputImage else { return image }

    // Create colored border
    guard let colorGenerator = CIFilter(name: "CIConstantColorGenerator") else { return image }
    colorGenerator.setValue(color, forKey: kCIInputColorKey)
    guard let colorImage = colorGenerator.outputImage?.cropped(to: expandedMask.extent) else {
      return image
    }

    // Apply mask to create border shape
    let borderFilter = CIFilter.blendWithMask()
    borderFilter.inputImage = colorImage
    borderFilter.maskImage = expandedMask
    borderFilter.backgroundImage = CIImage.empty()

    guard let coloredBorder = borderFilter.outputImage else { return image }

    // Composite original image over border
    let compositeFilter = CIFilter.sourceOverCompositing()
    compositeFilter.inputImage = image
    compositeFilter.backgroundImage = coloredBorder

    return compositeFilter.outputImage ?? image
  }
}

// MARK: - Color Parser
private class ColorParser {
  static func parse(_ colorString: String?) -> CIColor {
    guard let colorString = colorString else { return CIColor.white }

    let hex = colorString.hasPrefix("#") ? String(colorString.dropFirst()) : colorString

    guard hex.count == 6, let hexValue = UInt64(hex, radix: 16) else {
      return CIColor.white
    }

    let red = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
    let green = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
    let blue = CGFloat(hexValue & 0x0000FF) / 255.0

    return CIColor(red: red, green: green, blue: blue)
  }
}

// Add this extension at the end of the file
extension UIImage.Orientation {
  var exifOrientation: Int {
    switch self {
    case .up: return 1
    case .down: return 3
    case .left: return 8
    case .right: return 6
    case .upMirrored: return 2
    case .downMirrored: return 4
    case .leftMirrored: return 5
    case .rightMirrored: return 7
    @unknown default: return 1
    }
  }
}
