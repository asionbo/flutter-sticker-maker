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
      makeSticker(from: uiImage) { sticker in
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

  private func makeSticker(from image: UIImage, completion: @escaping (UIImage?) -> Void) {
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
        let stickerCIImage = self.apply(maskImage: maskCIImage, to: inputCIImage)
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

  private func apply(maskImage: CIImage, to inputImage: CIImage) -> CIImage {
    let filter = CIFilter.blendWithMask()
    filter.inputImage = inputImage
    filter.maskImage = maskImage
    filter.backgroundImage = CIImage.empty()
    return filter.outputImage!
  }
}