package com.ashutoshranjan.aero_hand_tracker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Bridges camera frames from Flutter to the MediaPipe Hand Landmarker.
 *
 * Frames arrive as NV21 bytes (camera plugin, ImageFormatGroup.nv21). They are
 * converted to ARGB while being downsampled (the landmark model runs at 224px
 * so full resolution is wasted work), rotated upright, then detected in VIDEO
 * running mode on a single background thread.
 */
class AeroHandTrackerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var assets: FlutterPlugin.FlutterAssets

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var landmarker: HandLandmarker? = null
    private var lastTimestamp = 0L
    private var pixelBuffer = IntArray(0)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        assets = binding.flutterAssets
        channel = MethodChannel(binding.binaryMessenger, "aero_hand_tracker")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.execute {
            try {
                closeLandmarker()
            } catch (_: Throwable) {
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> executor.execute { initialize(call, result) }
            "detect" -> executor.execute { detect(call, result) }
            "dispose" -> executor.execute {
                try {
                    closeLandmarker()
                } catch (_: Throwable) {
                }
                post { result.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    private fun post(block: () -> Unit) = mainHandler.post(block)

    private fun closeLandmarker() {
        landmarker?.close()
        landmarker = null
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        try {
            closeLandmarker()
            val asset = call.argument<String>("modelAsset") ?: "assets/models/hand_landmarker.task"
            val useGpu = call.argument<Boolean>("useGpu") ?: false
            val base = BaseOptions.builder()
                .setModelAssetPath(assets.getAssetFilePathByName(asset))
                .setDelegate(if (useGpu) Delegate.GPU else Delegate.CPU)
                .build()
            val options = HandLandmarker.HandLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.VIDEO)
                .setNumHands(call.argument<Int>("maxHands") ?: 1)
                .setMinHandDetectionConfidence(call.argument<Double>("minDetectionConfidence")?.toFloat() ?: 0.5f)
                .setMinHandPresenceConfidence(call.argument<Double>("minPresenceConfidence")?.toFloat() ?: 0.5f)
                .setMinTrackingConfidence(call.argument<Double>("minTrackingConfidence")?.toFloat() ?: 0.5f)
                .build()
            landmarker = HandLandmarker.createFromOptions(context, options)
            lastTimestamp = 0L
            post { result.success(null) }
        } catch (e: Throwable) {
            post { result.error("init_failed", e.message, null) }
        }
    }

    private fun detect(call: MethodCall, result: MethodChannel.Result) {
        val lm = landmarker
        if (lm == null) {
            post { result.error("not_initialized", "Call initialize() first", null) }
            return
        }
        try {
            val bytes = call.argument<ByteArray>("bytes")!!
            val width = call.argument<Int>("width")!!
            val height = call.argument<Int>("height")!!
            val rotation = call.argument<Int>("rotation") ?: 0
            val format = call.argument<String>("format") ?: "nv21"
            val bytesPerRow = call.argument<Int>("bytesPerRow") ?: width
            var ts = (call.argument<Number>("timestampMs") ?: SystemClock.uptimeMillis()).toLong()
            if (ts <= lastTimestamp) ts = lastTimestamp + 1
            lastTimestamp = ts

            val started = SystemClock.uptimeMillis()
            val step = if (maxOf(width, height) >= 960) 3 else if (maxOf(width, height) >= 480) 2 else 1
            val bitmap = when (format) {
                "bgra8888" -> bgraToBitmap(bytes, width, height, bytesPerRow, step)
                else -> nv21ToBitmap(bytes, width, height, bytesPerRow, step)
            }
            val upright = rotate(bitmap, rotation)
            val mpImage = BitmapImageBuilder(upright).build()
            val res = lm.detectForVideo(mpImage, ts)

            val hands = ArrayList<Map<String, Any>>()
            val all = res.landmarks()
            for (i in all.indices) {
                val pts = DoubleArray(all[i].size * 3)
                all[i].forEachIndexed { j, p ->
                    pts[j * 3] = p.x().toDouble()
                    pts[j * 3 + 1] = p.y().toDouble()
                    pts[j * 3 + 2] = p.z().toDouble()
                }
                val cat = res.handedness().getOrNull(i)?.firstOrNull()
                hands.add(
                    mapOf(
                        "landmarks" to pts,
                        "handedness" to (cat?.categoryName() ?: "Unknown"),
                        "score" to (cat?.score()?.toDouble() ?: 0.0),
                    )
                )
            }
            val payload = mapOf(
                "hands" to hands,
                "imageWidth" to upright.width,
                "imageHeight" to upright.height,
                "inferenceMs" to (SystemClock.uptimeMillis() - started).toInt(),
            )
            post { result.success(payload) }
        } catch (e: Throwable) {
            post { result.error("detect_failed", e.message, null) }
        }
    }

    private fun ensureBuffer(size: Int): IntArray {
        if (pixelBuffer.size != size) pixelBuffer = IntArray(size)
        return pixelBuffer
    }

    /** NV21 (Y plane followed by interleaved VU) → ARGB, downsampled by [step]. */
    private fun nv21ToBitmap(data: ByteArray, width: Int, height: Int, rowStride: Int, step: Int): Bitmap {
        val outW = width / step
        val outH = height / step
        val out = ensureBuffer(outW * outH)
        val stride = if (rowStride >= width) rowStride else width
        val uvStart = stride * height
        var o = 0
        for (oy in 0 until outH) {
            val y = oy * step
            val yRow = y * stride
            val uvRow = uvStart + (y shr 1) * stride
            for (ox in 0 until outW) {
                val x = ox * step
                val yy = (data[yRow + x].toInt() and 0xFF) - 16
                val uvIndex = uvRow + (x and 1.inv())
                val v = if (uvIndex < data.size) (data[uvIndex].toInt() and 0xFF) - 128 else 0
                val u = if (uvIndex + 1 < data.size) (data[uvIndex + 1].toInt() and 0xFF) - 128 else 0
                val c = if (yy < 0) 0 else 1192 * yy
                var r = (c + 1634 * v) shr 10
                var g = (c - 833 * v - 400 * u) shr 10
                var b = (c + 2066 * u) shr 10
                r = r.coerceIn(0, 255); g = g.coerceIn(0, 255); b = b.coerceIn(0, 255)
                out[o++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return Bitmap.createBitmap(out, outW, outH, Bitmap.Config.ARGB_8888)
    }

    private fun bgraToBitmap(data: ByteArray, width: Int, height: Int, rowStride: Int, step: Int): Bitmap {
        val outW = width / step
        val outH = height / step
        val out = ensureBuffer(outW * outH)
        var o = 0
        for (oy in 0 until outH) {
            val row = oy * step * rowStride
            for (ox in 0 until outW) {
                val i = row + ox * step * 4
                val b = data[i].toInt() and 0xFF
                val g = data[i + 1].toInt() and 0xFF
                val r = data[i + 2].toInt() and 0xFF
                out[o++] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        return Bitmap.createBitmap(out, outW, outH, Bitmap.Config.ARGB_8888)
    }

    private fun rotate(src: Bitmap, degrees: Int): Bitmap {
        val d = ((degrees % 360) + 360) % 360
        if (d == 0) return src
        val m = Matrix().apply { postRotate(d.toFloat()) }
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, false)
    }
}
