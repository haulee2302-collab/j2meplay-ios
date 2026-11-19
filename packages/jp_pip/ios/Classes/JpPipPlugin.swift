import Flutter
import UIKit
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo

public class JpPipPlugin: NSObject, FlutterPlugin {
  private var impl: Any?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "jp_pip", binaryMessenger: registrar.messenger())
    let instance = JpPipPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 15.0, *) else {
      result(call.method == "supported" ? false : nil)
      return
    }
    if impl == nil { impl = PipImpl() }
    let p = impl as! PipImpl
    switch call.method {
    case "supported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "setup":
      let args = call.arguments as? [String: Any]
      let auto = (args?["auto"] as? Bool) ?? true
      DispatchQueue.main.async { result(p.setup(auto: auto)) }
    case "frame":
      guard let args = call.arguments as? [String: Any],
            let data = args["data"] as? FlutterStandardTypedData,
            let w = args["w"] as? Int, let h = args["h"] as? Int else { result(nil); return }
      DispatchQueue.main.async {
        p.push(data.data, w, h)
        result(nil)
      }
    case "start":
      DispatchQueue.main.async { result(p.start()) }
    case "stop":
      DispatchQueue.main.async {
        p.pip?.stopPictureInPicture()
        result(nil)
      }
    case "dispose":
      DispatchQueue.main.async {
        p.teardown()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

@available(iOS 15.0, *)
final class PipImpl: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
  private var displayLayer: AVSampleBufferDisplayLayer?
  private var hostView: UIView?
  var pip: AVPictureInPictureController?

  func start() -> Bool {
    guard let p = pip, p.isPictureInPicturePossible else { return false }
    p.startPictureInPicture()
    return true
  }

  private func keyWindow() -> UIWindow? {
    for scene in UIApplication.shared.connectedScenes {
      if let ws = scene as? UIWindowScene {
        if let w = ws.windows.first(where: { $0.isKeyWindow }) { return w }
        if let w = ws.windows.first { return w }
      }
    }
    return nil
  }

  func setup(auto: Bool) -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return false }
    if pip != nil {
      if #available(iOS 14.2, *) { pip?.canStartPictureInPictureAutomaticallyFromInline = auto }
      return true
    }
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {}
    guard let win = keyWindow() else { return false }
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
    host.alpha = 0.02
    host.isUserInteractionEnabled = false
    let layer = AVSampleBufferDisplayLayer()
    layer.frame = host.bounds
    layer.videoGravity = .resizeAspect
    host.layer.addSublayer(layer)
    win.insertSubview(host, at: 0)
    hostView = host
    displayLayer = layer
    let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
    let c = AVPictureInPictureController(contentSource: source)
    c.delegate = self
    c.requiresLinearPlayback = true
    if #available(iOS 14.2, *) { c.canStartPictureInPictureAutomaticallyFromInline = auto }
    pip = c
    return true
  }

  func teardown() {
    pip?.stopPictureInPicture()
    pip = nil
    displayLayer?.removeFromSuperlayer()
    displayLayer = nil
    hostView?.removeFromSuperview()
    hostView = nil
  }

  func push(_ data: Data, _ w: Int, _ h: Int) {
    guard let layer = displayLayer, w > 0, h > 0, data.count >= w * h * 4 else { return }
    var pb: CVPixelBuffer?
    let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess, let buf = pb else { return }
    CVPixelBufferLockBaseAddress(buf, [])
    if let base = CVPixelBufferGetBaseAddress(buf) {
      let bpr = CVPixelBufferGetBytesPerRow(buf)
      data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return }
        for y in 0..<h {
          let s = src + y * w * 4
          let d = base.assumingMemoryBound(to: UInt8.self) + y * bpr
          for x in 0..<w {
            d[x * 4] = s[x * 4 + 2]
            d[x * 4 + 1] = s[x * 4 + 1]
            d[x * 4 + 2] = s[x * 4]
            d[x * 4 + 3] = 255
          }
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(buf, [])
    var fmt: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buf, formatDescriptionOut: &fmt)
    guard let desc = fmt else { return }
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buf, formatDescription: desc, sampleTiming: &timing, sampleBufferOut: &sample)
    guard let sb = sample else { return }
    if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(arr) > 0 {
      let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
    if layer.status == .failed { layer.flush() }
    layer.enqueue(sb)
  }

  // MARK: AVPictureInPictureSampleBufferPlaybackDelegate
  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

  func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
    return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
    return false
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
    completionHandler()
  }
}
