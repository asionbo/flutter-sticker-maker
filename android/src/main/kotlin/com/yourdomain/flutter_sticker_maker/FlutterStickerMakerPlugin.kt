package com.yourdomain.flutter_sticker_maker

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenter
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class FlutterStickerMakerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_sticker_maker")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "makeSticker") {
            val imageBytes = call.argument<ByteArray>("image")
            if (imageBytes != null) {
                processSticker(imageBytes, result)
            } else {
                result.error("NO_IMAGE", "No image provided", null)
            }
        } else {
            result.notImplemented()
        }
    }

    private fun processSticker(imageBytes: ByteArray, result: MethodChannel.Result) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val inputImage = InputImage.fromBitmap(bitmap, 0)
        val options = SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
            .build()
        val segmenter = SelfieSegmenter.getClient(options)

        segmenter.process(inputImage)
            .addOnSuccessListener { segmentationMask ->
                val mask = segmentationMask.buffer
                mask.rewind()
                val maskWidth = segmentationMask.width
                val maskHeight = segmentationMask.height
                val maskArray = FloatArray(maskWidth * maskHeight)
                mask.asFloatBuffer().get(maskArray)
                val stickerBitmap = Bitmap.createBitmap(maskWidth, maskHeight, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(stickerBitmap)
                val paint = Paint()
                for (y in 0 until maskHeight) {
                    for (x in 0 until maskWidth) {
                        val maskVal = maskArray[y * maskWidth + x]
                        val pixelColor = bitmap.getPixel(x * bitmap.width / maskWidth, y * bitmap.height / maskHeight)
                        if (maskVal > 0.5f) {
                            stickerBitmap.setPixel(x, y, pixelColor)
                        } else {
                            stickerBitmap.setPixel(x, y, 0x00000000)
                        }
                    }
                }
                val outputStream = ByteArrayOutputStream()
                stickerBitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
                val outputBytes = outputStream.toByteArray()
                Handler(Looper.getMainLooper()).post {
                    result.success(outputBytes)
                }
            }
            .addOnFailureListener { e ->
                Handler(Looper.getMainLooper()).post {
                    result.error("SEGMENTATION_FAILED", e.localizedMessage, null)
                }
            }
    }
}