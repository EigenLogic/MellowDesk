import AVFoundation
import AppKit
import QuartzCore
import SwiftUI

/// A lightweight camera preview. Mirroring is presentation-only; Vision receives
/// the original, unmirrored sample buffer so its coordinate system stays stable.
public struct CameraPreviewView: NSViewRepresentable {
  public let session: AVCaptureSession
  public var isMirrored: Bool

  public init(session: AVCaptureSession, isMirrored: Bool = true) {
    self.session = session
    self.isMirrored = isMirrored
  }

  public func makeNSView(context: Context) -> CameraPreviewNSView {
    let view = CameraPreviewNSView()
    view.previewLayer.session = session
    view.previewLayer.videoGravity = .resizeAspectFill
    view.setMirrored(isMirrored)
    return view
  }

  public func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
    if nsView.previewLayer.session !== session {
      nsView.previewLayer.session = session
    }
    nsView.setMirrored(isMirrored)
  }
}

public final class CameraPreviewNSView: NSView {
  public let previewLayer = AVCaptureVideoPreviewLayer()

  public override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer = previewLayer
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func layout() {
    super.layout()
    previewLayer.frame = bounds
  }

  fileprivate func setMirrored(_ mirrored: Bool) {
    // A layer transform works even before the capture connection exists.
    // The data-output connection remains unmirrored for Vision.
    previewLayer.transform =
      mirrored
      ? CATransform3DMakeScale(-1, 1, 1)
      : CATransform3DIdentity
  }
}
