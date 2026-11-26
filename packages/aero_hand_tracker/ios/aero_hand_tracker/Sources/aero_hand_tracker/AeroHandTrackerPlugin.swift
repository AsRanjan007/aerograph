import Flutter
import UIKit
import CoreVideo
import MediaPipeTasksVision

/// Bridges camera frames (BGRA8888 from the camera plugin) to the MediaPipe
/// Hand Landmarker running in video mode on a serial background queue.
public class AeroHandTrackerPlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private let queue = DispatchQueue(label: "com.ashutoshranjan.aero_hand_tracker", qos: .userInitiated)
  private var landmarker: HandLandmarker?
  private var lastTimestamp = 0

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "aero_hand_tracker", binaryMessenger: registrar.messenger())
    let instance = AeroHandTrackerPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      queue.async { self.initialize(args, result) }
    case "detect":
      queue.async { self.detect(args, result) }
    case "dispose":
      queue.async {
        self.landmarker = nil
        DispatchQueue.main.async { result(nil) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func initialize(_ args: [String: Any], _ result: @escaping FlutterResult) {
    let asset = args["modelAsset"] as? String ?? "assets/models/hand_landmarker.task"
    let key = registrar.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
      reply(result, FlutterError(code: "model_missing", message: "Model asset not found: \(asset)", details: nil))
      return
    }
    do {
      let options = HandLandmarkerOptions()
      options.baseOptions.modelAssetPath = path
      options.baseOptions.delegate = (args["useGpu"] as? Bool ?? false) ? .GPU : .CPU
      options.runningMode = .video
      options.numHands = args["maxHands"] as? Int ?? 1
      options.minHandDetectionConfidence = Float(args["minDetectionConfidence"] as? Double ?? 0.5)
      options.minHandPresenceConfidence = Float(args["minPresenceConfidence"] as? Double ?? 0.5)
      options.minTrackingConfidence = Float(args["minTrackingConfidence"] as? Double ?? 0.5)
      landmarker = try HandLandmarker(options: options)
      lastTimestamp = 0
      reply(result, nil)
    } catch {
      reply(result, FlutterError(code: "init_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func detect(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let landmarker = landmarker else {
      reply(result, FlutterError(code: "not_initialized", message: "Call initialize() first", details: nil))
      return
    }
    guard
      let data = args["bytes"] as? FlutterStandardTypedData,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int
    else {
      reply(result, FlutterError(code: "bad_args", message: "Missing frame data", details: nil))
      return
    }
    let bytesPerRow = args["bytesPerRow"] as? Int ?? width * 4
    let rotation = ((args["rotation"] as? Int ?? 0) % 360 + 360) % 360
    var ts = args["timestampMs"] as? Int ?? Int(Date().timeIntervalSince1970 * 1000)
    if ts <= lastTimestamp { ts = lastTimestamp + 1 }
    lastTimestamp = ts

    let started = CACurrentMediaTime()
    guard let pixelBuffer = makePixelBuffer(data.data, width: width, height: height, bytesPerRow: bytesPerRow) else {
      reply(result, FlutterError(code: "buffer_failed", message: "Could not create pixel buffer", details: nil))
      return
    }
    do {
      let image = try MPImage(pixelBuffer: pixelBuffer, orientation: orientation(for: rotation))
      let res = try landmarker.detect(videoFrame: image, timestampInMilliseconds: ts)
      var hands: [[String: Any]] = []
      for (i, points) in res.landmarks.enumerated() {
        var flat: [Double] = []
        flat.reserveCapacity(points.count * 3)
        for p in points {
          flat.append(Double(p.x)); flat.append(Double(p.y)); flat.append(Double(p.z))
        }
        let cat = i < res.handedness.count ? res.handedness[i].first : nil
        hands.append([
          "landmarks": flat,
          "handedness": cat?.categoryName ?? "Unknown",
          "score": Double(cat?.score ?? 0),
        ])
      }
      let swap = rotation == 90 || rotation == 270
      reply(result, [
        "hands": hands,
        "imageWidth": swap ? height : width,
        "imageHeight": swap ? width : height,
        "inferenceMs": Int((CACurrentMediaTime() - started) * 1000),
      ])
    } catch {
      reply(result, FlutterError(code: "detect_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func orientation(for rotation: Int) -> UIImage.Orientation {
    switch rotation {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }

  private func makePixelBuffer(_ data: Data, width: Int, height: Int, bytesPerRow: Int) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                     attrs as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let pb = buffer else { return nil }
    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }
    guard let dst = CVPixelBufferGetBaseAddress(pb) else { return nil }
    let dstStride = CVPixelBufferGetBytesPerRow(pb)
    let rowBytes = min(width * 4, bytesPerRow, dstStride)
    data.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
      guard let base = src.baseAddress else { return }
      for row in 0..<height {
        let srcOffset = row * bytesPerRow
        if srcOffset + rowBytes > src.count { break }
        memcpy(dst.advanced(by: row * dstStride), base.advanced(by: srcOffset), rowBytes)
      }
    }
    return pb
  }
}
