import Flutter
import UIKit
import Vision
import CoreImage.CIFilterBuiltins
import os.log

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
enum StickerMakerError: Error, LocalizedError {
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
    private let logger = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "StickerMaker", category: "Plugin")
    private let imageProcessor = ImageProcessor()
    private let maskGenerator = MaskGenerator()
    private let borderRenderer = BorderRenderer()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: StickerMakerConfig.channelName, binaryMessenger: registrar.messenger())
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
                    os_log("Parameter validation failed: %@", log: logger, type: .error, error.localizedDescription)
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: error.localizedDescription, details: nil))
                }
            } else {
                // For iOS < 17.0, delegate to Dart ONNX implementation
                result(FlutterError(code: "UNSUPPORTED_VERSION", message: "iOS version < 17.0 should use ONNX implementation", details: nil))
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
              let uiImage = UIImage(data: imageData.data) else {
            throw StickerMakerError.invalidImageData
        }
        
        let addBorder = args["addBorder"] as? Bool ?? false
        let borderColor = ColorParser.parse(args["borderColor"] as? String)
        let borderWidth = CGFloat(args["borderWidth"] as? Double ?? StickerMakerConfig.defaultBorderWidth)
        
        return StickerParameters(
            image: uiImage,
            addBorder: addBorder,
            borderColor: borderColor,
            borderWidth: max(0, borderWidth) // Ensure non-negative
        )
    }
    
    private func processSticker(with parameters: StickerParameters, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INTERNAL_ERROR", message: "Plugin instance deallocated", details: nil))
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
                os_log("Sticker creation failed: %@", log: self.logger, type: .error, error.localizedDescription)
                DispatchQueue.main.async {
                    result(FlutterError(code: "PROCESSING_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func createSticker(from parameters: StickerParameters) throws -> UIImage {
        // Step 1: Preprocess image
        let preprocessedImage = try imageProcessor.preprocess(parameters.image)
        
        // Step 2: Generate mask
        let maskImage = try maskGenerator.generateMask(for: preprocessedImage)
        
        // Step 3: Apply mask and optional border
        let ciImage = CIImage(image: preprocessedImage) ?? CIImage()
        let maskedImage = try applyMask(maskImage, to: ciImage)
        
        let finalImage = parameters.addBorder ?
            borderRenderer.addBorder(to: maskedImage, mask: maskImage, color: parameters.borderColor, width: parameters.borderWidth) :
            maskedImage
        
        // Step 4: Render final image
        return try renderImage(finalImage)
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
    
    private func renderImage(_ ciImage: CIImage) throws -> UIImage {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw StickerMakerError.imageRenderingFailed
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Supporting Types
private struct StickerParameters {
    let image: UIImage
    let addBorder: Bool
    let borderColor: CIColor
    let borderWidth: CGFloat
}

// MARK: - Image Processor
private class ImageProcessor {
    func preprocess(_ image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw StickerMakerError.unsupportedImageFormat
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
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
              let processedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw StickerMakerError.imagePreprocessingFailed
        }
        
        return UIImage(cgImage: processedCGImage)
    }
}

// MARK: - Mask Generator
@available(iOS 17.0, *)
private class MaskGenerator {
    func generateMask(for image: UIImage) throws -> CIImage {
        guard let inputCIImage = CIImage(image: image) else {
            throw StickerMakerError.invalidImageData
        }
        
        let handler = VNImageRequestHandler(ciImage: inputCIImage, options: [
            VNImageOption.cameraIntrinsics: NSNull(),
            VNImageOption.ciContext: CIContext(options: [.useSoftwareRenderer: false])
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
            maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        } catch {
            // If generateScaledMaskForImage fails, throw the mask generation error
            throw StickerMakerError.maskGenerationFailed
        }
        
        let maskCIImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        return smoothMaskEdges(maskCIImage)
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
        guard let colorImage = colorGenerator.outputImage?.cropped(to: expandedMask.extent) else { return image }
        
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