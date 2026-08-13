import AVFoundation
import Combine
import CoreVideo
import MellowDeskCore
import OSLog

/// Owns the camera for the duration of one exercise session and publishes raw
/// head-pose samples on the main queue.
///
/// Session configuration and lifecycle calls run on `captureQueue`. Frame
/// delivery and Vision inference run on a separate serial `videoOutputQueue`.
/// No frame is recorded, retained after processing, or sent over the network.
public final class CameraCaptureService: NSObject, ObservableObject {
  public typealias MotionSampleHandler = (MotionSample) -> Void

  public let captureSession = AVCaptureSession()

  @Published public private(set) var authorizationState: CameraAuthorizationState
  @Published public private(set) var isRunning = false
  @Published public private(set) var isStarting = false
  @Published public private(set) var captureError: CameraCaptureError?
  @Published public private(set) var latestMotionSample: MotionSample?
  @Published public private(set) var activeCameraName: String?

  /// Called on the main queue after `latestMotionSample` is updated.
  public var motionSampleHandler: MotionSampleHandler?

  private let captureQueue = DispatchQueue(
    label: "cn.eigenlogic.mellowdesk.camera.capture-session",
    qos: .userInitiated
  )
  private let videoOutputQueue = DispatchQueue(
    label: "cn.eigenlogic.mellowdesk.camera.video-output",
    qos: .userInitiated
  )
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "cn.eigenlogic.mellowdesk",
    category: "camera-authorization"
  )
  private let captureQueueKey = DispatchSpecificKey<UInt8>()
  private let sampleStateLock = NSLock()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let estimator: VisionHeadPoseEstimator
  private var notificationObservers: [NSObjectProtocol] = []

  // Accessed only on captureQueue.
  private var isConfigured = false
  private var wantsToRun = false

  // Shared with videoOutputQueue and protected by sampleStateLock.
  private var acceptsSamples = false
  private var sampleGeneration: UInt64 = 0

  public init(estimator: VisionHeadPoseEstimator = VisionHeadPoseEstimator()) {
    authorizationState = CameraAuthorizationState(
      AVCaptureDevice.authorizationStatus(for: .video)
    )
    self.estimator = estimator
    super.init()
    captureQueue.setSpecific(key: captureQueueKey, value: 1)
    observeSessionNotifications()
  }

  deinit {
    notificationObservers.forEach(NotificationCenter.default.removeObserver)
    setAcceptsSamples(false)
    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    performOnCaptureQueueSync {
      if captureSession.isRunning {
        captureSession.stopRunning()
      }
      tearDownSession()
    }
  }

  /// Requests permission if necessary, configures the camera, and starts it
  /// without blocking the main thread.
  public func start() {
    publishOnMain { service in
      service.captureError = nil
      service.isStarting = true
    }

    captureQueue.async { [weak self] in
      guard let self else { return }
      self.wantsToRun = true
      self.startAccordingToCurrentAuthorization()
    }
  }

  /// Stops capture and removes all inputs/outputs so macOS can immediately
  /// release the camera for other applications.
  public func stop() {
    // Close the delivery gate synchronously. Incrementing the generation also
    // prevents an already-queued main-thread callback from an older session
    // being accepted after a rapid stop/start cycle.
    setAcceptsSamples(false)
    captureQueue.async { [weak self] in
      guard let self else { return }
      self.wantsToRun = false
      self.setAcceptsSamples(false)
      if self.captureSession.isRunning {
        self.captureSession.stopRunning()
      }
      self.tearDownSession()
      self.videoOutputQueue.sync {
        self.estimator.reset()
      }

      self.publishOnMain { service in
        service.isRunning = false
        service.isStarting = false
        service.activeCameraName = nil
        service.latestMotionSample = nil
      }
    }
  }

  /// Refreshes permission state after a user returns from System Settings.
  public func refreshAuthorizationState() {
    let state = CameraAuthorizationState(
      AVCaptureDevice.authorizationStatus(for: .video)
    )
    publishOnMain { $0.authorizationState = state }
  }

  private func startAccordingToCurrentAuthorization() {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    let state = CameraAuthorizationState(status)
    logger.notice(
      "Camera authorization evaluated; status=\(self.authorizationStatusName(status), privacy: .public); bundleID=\(self.bundleIdentifier, privacy: .public)"
    )
    publishOnMain { $0.authorizationState = state }

    switch status {
    case .authorized:
      configureAndStartIfNeeded()

    case .notDetermined:
      logger.notice(
        "Camera authorization request started; bundleID=\(self.bundleIdentifier, privacy: .public)"
      )
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self else { return }
        self.logger.notice(
          "Camera authorization request completed; granted=\(granted, privacy: .public); bundleID=\(self.bundleIdentifier, privacy: .public)"
        )
        self.captureQueue.async {
          let updatedState: CameraAuthorizationState = granted ? .authorized : .denied
          self.publishOnMain { $0.authorizationState = updatedState }

          guard self.wantsToRun else {
            self.publishOnMain { $0.isStarting = false }
            return
          }

          if granted {
            self.configureAndStartIfNeeded()
          } else {
            self.fail(.permissionDenied)
          }
        }
      }

    case .denied:
      fail(.permissionDenied)

    case .restricted:
      fail(.permissionRestricted)

    @unknown default:
      fail(.permissionRestricted)
    }
  }

  // Must run on captureQueue.
  private func configureAndStartIfNeeded() {
    guard wantsToRun else {
      publishOnMain { $0.isStarting = false }
      return
    }

    guard !captureSession.isRunning else {
      setAcceptsSamples(true)
      publishOnMain { service in
        service.isRunning = true
        service.isStarting = false
        service.captureError = nil
      }
      return
    }

    do {
      if !isConfigured {
        try configureSession()
      }
    } catch let error as CameraCaptureError {
      fail(error)
      return
    } catch {
      fail(.configurationFailed(error.localizedDescription))
      return
    }

    videoOutputQueue.sync {
      estimator.reset()
    }
    captureSession.startRunning()
    guard captureSession.isRunning else {
      fail(.startFailed)
      return
    }
    setAcceptsSamples(true)

    publishOnMain { service in
      service.isRunning = true
      service.isStarting = false
      service.captureError = nil
    }
  }

  // Must run on captureQueue.
  private func configureSession() throws {
    guard let camera = preferredCamera() else {
      throw CameraCaptureError.noCameraAvailable
    }

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: camera)
    } catch {
      throw CameraCaptureError.cannotCreateInput(error.localizedDescription)
    }

    captureSession.beginConfiguration()
    defer { captureSession.commitConfiguration() }

    guard captureSession.canSetSessionPreset(.vga640x480) else {
      throw CameraCaptureError.configurationFailed(
        "The selected camera does not support a 640 x 480 capture preset."
      )
    }
    captureSession.sessionPreset = .vga640x480

    guard captureSession.canAddInput(input) else {
      throw CameraCaptureError.cannotAddInput
    }
    captureSession.addInput(input)
    // Mark partial ownership so a later configuration failure tears the
    // input back down instead of leaving the device attached.
    isConfigured = true

    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

    guard captureSession.canAddOutput(videoOutput) else {
      videoOutput.setSampleBufferDelegate(nil, queue: nil)
      throw CameraCaptureError.cannotAddOutput
    }
    captureSession.addOutput(videoOutput)
    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: preferredPixelFormat()
    ]

    // Keep analysis coordinates unmirrored. CameraPreviewView mirrors only
    // its own preview connection, so Vision angle signs remain stable.
    if let connection = videoOutput.connection(with: .video),
      connection.isVideoMirroringSupported
    {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = false
    }

    publishOnMain { $0.activeCameraName = camera.localizedName }
  }

  // Must run on captureQueue.
  private func tearDownSession() {
    guard isConfigured else { return }

    videoOutput.setSampleBufferDelegate(nil, queue: nil)
    captureSession.beginConfiguration()
    captureSession.inputs.forEach(captureSession.removeInput)
    captureSession.outputs.forEach(captureSession.removeOutput)
    captureSession.commitConfiguration()
    isConfigured = false
  }

  private func preferredCamera() -> AVCaptureDevice? {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
      mediaType: .video,
      position: .unspecified
    )

    let devices = discovery.devices
    return devices.first {
      $0.deviceType == .builtInWideAngleCamera && $0.position == .front
    } ?? devices.first {
      $0.deviceType == .builtInWideAngleCamera
    } ?? AVCaptureDevice.default(for: .video)
  }

  private func preferredPixelFormat() -> OSType {
    let availableFormats = videoOutput.availableVideoPixelFormatTypes
    let efficientFormats: [OSType] = [
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_32BGRA,
    ]

    return efficientFormats.first(where: availableFormats.contains)
      ?? availableFormats.first
      ?? kCVPixelFormatType_32BGRA
  }

  private func observeSessionNotifications() {
    let center = NotificationCenter.default
    notificationObservers.append(
      center.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification,
        object: captureSession,
        queue: nil
      ) { [weak self] notification in
        let message =
          (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?
          .localizedDescription ?? "Unknown AVFoundation error."

        self?.captureQueue.async { [weak self] in
          guard let self, self.wantsToRun else { return }
          self.fail(.sessionRuntimeFailure(message))
        }
      }
    )

    notificationObservers.append(
      center.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification,
        object: captureSession,
        queue: nil
      ) { [weak self] _ in
        self?.captureQueue.async { [weak self] in
          guard let self, self.wantsToRun else { return }
          self.setAcceptsSamples(false)
          self.publishOnMain { service in
            service.isRunning = false
            service.captureError = .sessionInterrupted
          }
        }
      }
    )

    notificationObservers.append(
      center.addObserver(
        forName: AVCaptureSession.interruptionEndedNotification,
        object: captureSession,
        queue: nil
      ) { [weak self] _ in
        self?.captureQueue.async { [weak self] in
          guard let self, self.wantsToRun else { return }
          self.configureAndStartIfNeeded()
        }
      }
    )
  }

  // Must run on captureQueue.
  private func fail(_ error: CameraCaptureError) {
    logger.error(
      "Camera capture failed; reason=\(self.diagnosticName(for: error), privacy: .public); bundleID=\(self.bundleIdentifier, privacy: .public)"
    )
    wantsToRun = false
    setAcceptsSamples(false)
    if captureSession.isRunning {
      captureSession.stopRunning()
    }
    tearDownSession()

    publishOnMain { service in
      service.captureError = error
      service.isRunning = false
      service.isStarting = false
      service.activeCameraName = nil
    }
  }

  private func publishOnMain(_ update: @escaping (CameraCaptureService) -> Void) {
    if Thread.isMainThread {
      update(self)
    } else {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        update(self)
      }
    }
  }

  private var bundleIdentifier: String {
    Bundle.main.bundleIdentifier ?? "unknown"
  }

  private func authorizationStatusName(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return "unknown(\(status.rawValue))"
    }
  }

  private func diagnosticName(for error: CameraCaptureError) -> String {
    switch error {
    case .permissionDenied:
      return "permissionDenied"
    case .permissionRestricted:
      return "permissionRestricted"
    case .noCameraAvailable:
      return "noCameraAvailable"
    case .cannotCreateInput:
      return "cannotCreateInput"
    case .cannotAddInput:
      return "cannotAddInput"
    case .cannotAddOutput:
      return "cannotAddOutput"
    case .configurationFailed:
      return "configurationFailed"
    case .sessionInterrupted:
      return "sessionInterrupted"
    case .sessionRuntimeFailure:
      return "sessionRuntimeFailure"
    case .visionProcessingFailed:
      return "visionProcessingFailed"
    case .startFailed:
      return "startFailed"
    }
  }

  private func performOnCaptureQueueSync(_ work: () -> Void) {
    if DispatchQueue.getSpecific(key: captureQueueKey) != nil {
      work()
    } else {
      captureQueue.sync(execute: work)
    }
  }

  private func setAcceptsSamples(_ acceptsSamples: Bool) {
    sampleStateLock.lock()
    if !acceptsSamples {
      sampleGeneration &+= 1
    }
    self.acceptsSamples = acceptsSamples
    sampleStateLock.unlock()
  }

  private func acceptedSampleGeneration() -> UInt64? {
    sampleStateLock.lock()
    let result = acceptsSamples ? sampleGeneration : nil
    sampleStateLock.unlock()
    return result
  }

  private func shouldAcceptSamples(generation: UInt64) -> Bool {
    sampleStateLock.lock()
    let result = acceptsSamples && sampleGeneration == generation
    sampleStateLock.unlock()
    return result
  }

  private func publishInvalidMotionSample(
    generation: UInt64,
    error: CameraCaptureError? = nil
  ) {
    let sample = MotionSample(
      timestamp: ProcessInfo.processInfo.systemUptime,
      yawDegrees: nil,
      pitchDegrees: nil,
      rollDegrees: nil,
      trackingQuality: 0,
      isFaceValid: false,
      faceCount: 0
    )
    publishOnMain { service in
      guard service.shouldAcceptSamples(generation: generation) else { return }
      if let error {
        service.captureError = error
      }
      service.latestMotionSample = sample
      service.motionSampleHandler?(sample)
    }
  }
}

extension CameraCaptureService: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let generation = acceptedSampleGeneration() else { return }

    do {
      guard let sample = try estimator.process(sampleBuffer) else {
        return
      }

      guard shouldAcceptSamples(generation: generation) else { return }

      publishOnMain { service in
        guard service.shouldAcceptSamples(generation: generation) else { return }
        if case .visionProcessingFailed? = service.captureError {
          service.captureError = nil
        }
        service.latestMotionSample = sample
        service.motionSampleHandler?(sample)
      }
    } catch {
      // A transient Vision failure doesn't take ownership away from the
      // camera. Deliver an invalid sample before any later valid frame so
      // calibration and hold evidence cannot span the processing gap.
      publishInvalidMotionSample(
        generation: generation,
        error: .visionProcessingFailed(error.localizedDescription)
      )
    }
  }

  public func captureOutput(
    _ output: AVCaptureOutput,
    didDrop sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let generation = acceptedSampleGeneration() else { return }
    publishInvalidMotionSample(generation: generation)
  }
}
