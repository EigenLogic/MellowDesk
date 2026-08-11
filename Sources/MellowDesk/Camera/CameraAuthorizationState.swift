import AVFoundation

/// Camera permission state exposed to the app UI.
public enum CameraAuthorizationState: Equatable {
  case notDetermined
  case authorized
  case denied
  case restricted

  init(_ status: AVAuthorizationStatus) {
    switch status {
    case .notDetermined:
      self = .notDetermined
    case .authorized:
      self = .authorized
    case .denied:
      self = .denied
    case .restricted:
      self = .restricted
    @unknown default:
      self = .restricted
    }
  }
}

/// Errors that can prevent camera-backed exercise tracking.
public enum CameraCaptureError: LocalizedError, Equatable {
  case permissionDenied
  case permissionRestricted
  case noCameraAvailable
  case cannotCreateInput(String)
  case cannotAddInput
  case cannotAddOutput
  case configurationFailed(String)
  case sessionInterrupted
  case sessionRuntimeFailure(String)
  case visionProcessingFailed(String)
  case startFailed

  public var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return "Camera access was denied."
    case .permissionRestricted:
      return "Camera access is restricted on this Mac."
    case .noCameraAvailable:
      return "No available camera was found."
    case .cannotCreateInput(let message):
      return "The camera input could not be created: \(message)"
    case .cannotAddInput:
      return "The camera input could not be added to the capture session."
    case .cannotAddOutput:
      return "The video output could not be added to the capture session."
    case .configurationFailed(let message):
      return "Camera configuration failed: \(message)"
    case .sessionInterrupted:
      return "The camera session was interrupted."
    case .sessionRuntimeFailure(let message):
      return "The camera session stopped unexpectedly: \(message)"
    case .visionProcessingFailed(let message):
      return "Head-pose processing failed: \(message)"
    case .startFailed:
      return "The camera capture session did not start."
    }
  }
}
