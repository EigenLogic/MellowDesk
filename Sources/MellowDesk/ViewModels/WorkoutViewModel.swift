import AppKit
import Combine
import Foundation
import MellowDeskCore
import SwiftUI

@MainActor
final class WorkoutViewModel: ObservableObject {
  enum Phase: Equatable {
    case ready
    case calibrating
    case calibratingDirection
    case exercising
    case transitioning
    case completed
  }

  private enum DirectionCalibrationStage {
    case seekingMovement
    case returningToNeutral
  }

  let plan = ExercisePlan.v1
  let cameraService: CameraCaptureService

  @Published private(set) var phase: Phase = .ready
  @Published private(set) var currentExerciseIndex = 0
  @Published private(set) var currentRepetitions = 0
  @Published private(set) var calibrationProgress = 0.0
  @Published private(set) var usesCamera = true
  @Published private(set) var isPaused = false
  @Published private(set) var completedResults: [ExerciseResult] = []
  @Published private(set) var elapsedDuration: TimeInterval = 0
  @Published private(set) var didSaveSession = false
  @Published private(set) var liveGuidanceText = "请保持正脸在画面中"
  @Published var isShowingCameraError = false
  @Published private(set) var cameraErrorTitle = "无法使用摄像头"
  @Published private(set) var cameraErrorMessage: String?

  private let appModel: AppModel
  private let initialCameraAuthorizationDidResolve: () -> Void
  private var calibrationSamples: [MotionSample] = []
  private var calibrationProfile: CalibrationProfile?
  private var repCounter: RepCounter?
  private var latestSample: MotionSample?
  private var startedAt: Date?
  private var transitionWorkItem: DispatchWorkItem?
  private var initialCameraAuthorizationFocusCancellable: AnyCancellable?
  private var cancellables: Set<AnyCancellable> = []
  private var savedSession = false
  private var didClose = false
  private var everUsedCamera = false
  private var trackingWasLost = false
  private var calibrationInvalidSince: TimeInterval?
  private var calibrationFailureCount = 0
  private var directionCalibrationStage: DirectionCalibrationStage = .seekingMovement
  private var directionCalibrationSign: Double?
  private var directionCalibrationLastTimestamp: TimeInterval?
  private var directionCalibrationMovementEvidence: TimeInterval = 0
  private var directionCalibrationMovementSampleCount = 0
  private var directionCalibrationPeakDegrees: Double = 0
  private var directionCalibrationNeutralEvidence: TimeInterval = 0
  private var directionCalibrationNeutralIsContinuous = false
  private var directionCalibrationInvalidSince: TimeInterval?
  private var directionCalibrationFilter = MedianEMAFilter(windowSize: 3, alpha: 0.5)
  private var isSuspendedForWindowVisibility = false

  init(
    appModel: AppModel,
    cameraService: CameraCaptureService = CameraCaptureService(),
    initialCameraAuthorizationDidResolve: @escaping () -> Void = {}
  ) {
    self.appModel = appModel
    self.cameraService = cameraService
    self.initialCameraAuthorizationDidResolve = initialCameraAuthorizationDidResolve

    cameraService.motionSampleHandler = { [weak self] sample in
      self?.consume(sample)
    }
    cameraService.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
    cameraService.$captureError
      .compactMap { $0 }
      .receive(on: RunLoop.main)
      .sink { [weak self] error in self?.handleCameraError(error) }
      .store(in: &cancellables)
  }

  deinit {
    transitionWorkItem?.cancel()
    initialCameraAuthorizationFocusCancellable?.cancel()
    cameraService.motionSampleHandler = nil
    cameraService.stop()
  }

  var currentExercise: ExerciseDefinition {
    plan.exercises[min(max(currentExerciseIndex, 0), plan.exercises.count - 1)]
  }

  var exerciseProgress: Double {
    guard currentExercise.targetRepetitions > 0 else { return 0 }
    return min(Double(currentRepetitions) / Double(currentExercise.targetRepetitions), 1)
  }

  var currentAnimationKind: ExerciseAnimationKind {
    switch currentExercise.kind {
    case .neckRotation: return .rotation
    case .lateralFlexion: return .lateralTilt
    case .gentleNod: return .nod
    }
  }

  var animationDirectionSign: Double? {
    let direction =
      phase == .calibratingDirection
      ? currentExercise.directions.first
      : repCounter?.expectedDirection
    guard let direction else { return nil }
    switch direction {
    case .left: return -1
    case .right, .down: return 1
    }
  }

  var instructionText: String {
    switch phase {
    case .calibrating:
      return "坐直、平视摄像头，肩膀自然放松。"
    case .calibratingDirection:
      if currentExercise.kind == .gentleNod {
        return "先做一次舒适的小幅低头并回正；这次只用于适配识别方向与幅度，不计入次数。"
      }
      return "先做一次小幅\(directionMovementText)，再缓慢回到正中；这次只用于适配摄像头方向，不计入次数。"
    case .transitioning:
      return "这个动作已完成，准备下一个动作。"
    default:
      guard let direction = repCounter?.expectedDirection else {
        return currentExercise.instruction
      }
      switch currentExercise.kind {
      case .neckRotation:
        return "缓慢转向\(direction.localizedName)，达到舒适范围后停留，再回到正中。"
      case .lateralFlexion:
        return "耳朵缓慢向\(direction.localizedName)肩膀靠近，肩膀保持放松。"
      case .gentleNod:
        return currentExercise.instruction
      }
    }
  }

  private var directionMovementText: String {
    let direction = currentExercise.directions.first
    switch currentExercise.kind {
    case .neckRotation:
      return direction == .right ? "向右转头" : "向左转头"
    case .lateralFlexion:
      return direction == .right ? "向右侧屈" : "向左侧屈"
    case .gentleNod:
      return "低头"
    }
  }

  var trackingStatusText: String {
    if !usesCamera { return "无需摄像头" }
    if cameraService.isStarting { return "正在开启" }
    guard cameraService.isRunning else { return "未连接" }
    guard let sample = latestSample else { return "寻找面部" }
    if sample.faceCount > 1 { return "多人入镜" }
    if sample.isFaceValid { return "识别正常" }
    return "请调整位置"
  }

  var canRestoreAfterInitialCameraAuthorization: Bool {
    usesCamera
      && !didClose
      && !isSuspendedForWindowVisibility
      && phase != .ready
      && phase != .completed
  }

  var trackingStatusIcon: String {
    if !usesCamera { return "hand.tap" }
    if cameraService.isStarting { return "camera.fill" }
    if latestSample?.isFaceValid == true { return "checkmark.circle.fill" }
    return "exclamationmark.triangle.fill"
  }

  var trackingStatusColor: Color {
    if !usesCamera || latestSample?.isFaceValid == true { return AppTheme.accent }
    return AppTheme.warning
  }

  var liveGuidanceColor: Color {
    if trackingWasLost || latestSample?.isFaceValid == false { return AppTheme.warning }
    return AppTheme.accent
  }

  func begin() {
    guard phase == .ready else { return }
    cameraService.refreshAuthorizationState()
    if cameraService.authorizationState == .notDetermined {
      initialCameraAuthorizationFocusCancellable = cameraService.$authorizationState
        .first { $0 != .notDetermined }
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
          self?.initialCameraAuthorizationResolved()
        }
    }
    startedAt = Date()
    appModel.workoutStarted()
    usesCamera = true
    startCalibration(resetCurrentExercise: true)
    cameraService.start()
  }

  func consume(_ sample: MotionSample) {
    guard usesCamera, !isPaused, !isSuspendedForWindowVisibility else { return }
    latestSample = sample
    if sample.isFaceValid {
      everUsedCamera = true
    }

    switch phase {
    case .calibrating:
      consumeCalibrationSample(sample)
    case .calibratingDirection:
      consumeDirectionCalibrationSample(sample)
    case .exercising:
      consumeExerciseSample(sample)
    case .ready, .transitioning, .completed:
      break
    }
  }

  func recordManualRepetition() {
    guard !usesCamera, phase == .exercising, !isPaused else { return }
    currentRepetitions = min(
      currentRepetitions + 1,
      currentExercise.targetRepetitions
    )
    playCountFeedback()
    if currentRepetitions >= currentExercise.targetRepetitions {
      completeCurrentExercise(mode: .manual)
    }
  }

  func useManualMode() {
    guard phase != .completed else { return }
    initialCameraAuthorizationFocusCancellable?.cancel()
    initialCameraAuthorizationFocusCancellable = nil
    let isTransitioning = phase == .transitioning
    cameraService.stop()
    usesCamera = false
    isPaused = false
    isShowingCameraError = false
    cameraErrorMessage = nil
    trackingWasLost = false

    if startedAt == nil { startedAt = Date() }
    if phase == .ready || phase == .calibrating || phase == .calibratingDirection {
      currentRepetitions = 0
    }
    repCounter = nil
    if isTransitioning {
      liveGuidanceText = "完成，准备下一个动作"
      return
    }
    phase = .exercising
    liveGuidanceText = "每次完成并回到中立位后，点击“完成 1 次”。"
  }

  func recalibrate() {
    guard usesCamera, phase == .exercising else { return }
    startCalibration(resetCurrentExercise: true)
  }

  func togglePause() {
    guard phase == .exercising else { return }
    invalidateCurrentAttempt()
    isPaused.toggle()
    liveGuidanceText = isPaused ? "训练已暂停" : "请回到中立位并保持"
  }

  func resumeCameraAfterSettings() {
    guard usesCamera,
      !isSuspendedForWindowVisibility,
      phase != .ready,
      phase != .completed,
      !cameraService.isRunning,
      !cameraService.isStarting
    else { return }
    cameraService.refreshAuthorizationState()
    guard cameraService.authorizationState == .authorized else { return }
    cameraService.start()
  }

  func openCameraSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    ) {
      NSWorkspace.shared.open(url)
    }
  }

  func name(for kind: ExerciseKind) -> String {
    plan.exercises.first(where: { $0.kind == kind })?.displayName ?? kind.rawValue
  }

  func workoutWindowDidBecomeHidden() {
    guard usesCamera,
      !isSuspendedForWindowVisibility,
      phase != .ready,
      phase != .completed
    else { return }
    initialCameraAuthorizationFocusCancellable?.cancel()
    initialCameraAuthorizationFocusCancellable = nil
    isSuspendedForWindowVisibility = true
    invalidateCurrentAttempt()
    if phase == .calibrating {
      calibrationSamples.removeAll(keepingCapacity: true)
      calibrationProgress = 0
    } else if phase == .calibratingDirection {
      resetDirectionCalibrationAttempt()
      calibrationProgress = 0
    }
    trackingWasLost = true
    cameraService.stop()
    liveGuidanceText = "窗口不可见，摄像头已关闭"
  }

  func workoutWindowDidBecomeVisible() {
    guard usesCamera, phase != .ready, phase != .completed else { return }
    guard isSuspendedForWindowVisibility else {
      resumeCameraAfterSettings()
      return
    }

    isSuspendedForWindowVisibility = false
    switch phase {
    case .calibrating:
      calibrationSamples.removeAll(keepingCapacity: true)
      calibrationProgress = 0
      liveGuidanceText = "保持正脸、平视屏幕，正在重新校准中立位…"
    case .calibratingDirection:
      resetDirectionCalibrationAttempt()
      calibrationProgress = 0
      liveGuidanceText = "请重新做一次小幅\(directionMovementText)"
    case .exercising:
      invalidateCurrentAttempt()
      liveGuidanceText = "请回到中立位并保持"
    case .transitioning:
      liveGuidanceText = "完成，准备下一个动作"
    case .ready, .completed:
      return
    }
    cameraService.refreshAuthorizationState()
    if cameraService.authorizationState == .authorized {
      cameraService.start()
    }
  }

  func windowDidClose(skipped: Bool = false) {
    guard !didClose else { return }
    didClose = true
    transitionWorkItem?.cancel()
    initialCameraAuthorizationFocusCancellable?.cancel()
    initialCameraAuthorizationFocusCancellable = nil
    cameraService.motionSampleHandler = nil
    cameraService.stop()
    if phase != .completed {
      appModel.workoutDismissed(skipped: skipped)
    }
  }

  private func startCalibration(resetCurrentExercise: Bool) {
    calibrationSamples.removeAll(keepingCapacity: true)
    calibrationProgress = 0
    calibrationProfile = nil
    calibrationInvalidSince = nil
    calibrationFailureCount = 0
    repCounter = nil
    resetDirectionCalibrationAttempt()
    trackingWasLost = false
    isPaused = false
    phase = .calibrating
    liveGuidanceText = "保持正脸、平视屏幕，正在校准中立位…"
    if resetCurrentExercise {
      currentRepetitions = 0
    }
  }

  private func initialCameraAuthorizationResolved() {
    initialCameraAuthorizationFocusCancellable = nil
    guard canRestoreAfterInitialCameraAuthorization else { return }
    initialCameraAuthorizationDidResolve()
  }

  private func consumeCalibrationSample(_ sample: MotionSample) {
    guard !isShowingCameraError else { return }
    let isUsable = MotionAxis.allCases.allSatisfy {
      sample.isUsable(for: $0, minimumTrackingQuality: 0.4)
    }
    guard isUsable else {
      trackingWasLost = true
      if calibrationInvalidSince == nil {
        calibrationInvalidSince = sample.timestamp
      }
      if let invalidSince = calibrationInvalidSince,
        sample.timestamp.isFinite,
        sample.timestamp - invalidSince >= 0.75
      {
        calibrationSamples.removeAll(keepingCapacity: true)
        calibrationProgress = 0
      }
      liveGuidanceText =
        sample.faceCount > 1
        ? "画面中请只保留一人"
        : "请让脸部保持完整入镜"
      return
    }

    trackingWasLost = false
    calibrationInvalidSince = nil
    calibrationSamples.append(sample)
    if calibrationSamples.count > 48 {
      calibrationSamples.removeFirst(calibrationSamples.count - 48)
    }
    let desiredSampleCount = 24
    calibrationProgress = min(
      Double(calibrationSamples.count) / Double(desiredSampleCount),
      1
    )
    liveGuidanceText =
      calibrationSamples.count < desiredSampleCount
      ? "很好，请继续保持中立位"
      : "校准完成"

    guard calibrationSamples.count >= desiredSampleCount else { return }

    do {
      let calibrator = NeutralCalibrator(
        minimumValidSamples: 18,
        noiseMultiplier: 2
      )
      calibrationProfile = try calibrator.calibrate(samples: calibrationSamples)
      beginDirectionCalibrationForCurrentExercise()
    } catch let error as NeutralCalibrationError {
      calibrationFailureCount += 1

      if calibrationFailureCount >= 3,
        let bestEffortProfile = try? NeutralCalibrator(
          minimumValidSamples: 18,
          noiseMultiplier: 2,
          rejectsUnstableSamples: false
        ).calibrate(samples: calibrationSamples)
      {
        calibrationProfile = bestEffortProfile
        liveGuidanceText = "基础校准完成，动作中会继续平滑识别"
        beginDirectionCalibrationForCurrentExercise()
        return
      }

      let discardCount = min(6, calibrationSamples.count)
      calibrationSamples.removeFirst(discardCount)
      calibrationProgress = min(Double(calibrationSamples.count) / Double(desiredSampleCount), 1)
      if case .unstableSamples = error {
        liveGuidanceText = "检测到头部移动，请保持正脸不动再试"
      } else {
        liveGuidanceText = "识别不够稳定，请保持正脸并调整光线"
      }
    } catch {
      cameraErrorTitle = "需要重新校准"
      cameraErrorMessage = "中立位校准暂时失败。请重试，或改用手动计次。"
      isShowingCameraError = true
    }
  }

  private func beginDirectionCalibrationForCurrentExercise() {
    guard usesCamera, calibrationProfile != nil else { return }
    phase = .calibratingDirection
    resetDirectionCalibrationAttempt()
    calibrationProgress = 0
    trackingWasLost = false
    liveGuidanceText = "请做一次小幅\(directionMovementText)"
  }

  private func consumeDirectionCalibrationSample(_ sample: MotionSample) {
    guard !isShowingCameraError else { return }
    guard
      sample.isUsable(for: currentExercise.axis, minimumTrackingQuality: 0.4),
      let rawValue = sample.value(for: currentExercise.axis),
      let axisCalibration = calibrationProfile?.calibration(for: currentExercise.axis)
    else {
      trackingWasLost = true
      let canPreserveNodReturn =
        currentExercise.kind == .gentleNod
        && directionCalibrationStage == .returningToNeutral
        && directionCalibrationSign != nil
        && sample.faceCount <= 1
        && sample.timestamp.isFinite
      if canPreserveNodReturn {
        let invalidSince =
          directionCalibrationInvalidSince
          ?? directionCalibrationLastTimestamp
          ?? sample.timestamp
        directionCalibrationInvalidSince = invalidSince
        let invalidDuration = sample.timestamp - invalidSince
        if invalidDuration >= 0, invalidDuration <= 1.2 {
          directionCalibrationLastTimestamp = sample.timestamp
          directionCalibrationNeutralEvidence = 0
          directionCalibrationNeutralIsContinuous = false
          directionCalibrationFilter.reset()
          calibrationProgress = 0.55
          liveGuidanceText = "低头时暂时没有看到完整脸部，请缓慢回正并面向屏幕"
          return
        }
      }
      resetDirectionCalibrationAttempt()
      calibrationProgress = 0
      liveGuidanceText =
        sample.faceCount > 1
        ? "画面中请只保留一人，然后重新完成适配动作"
        : "请让脸部完整入镜，然后重新完成适配动作"
      return
    }

    trackingWasLost = false
    directionCalibrationInvalidSince = nil
    let elapsed: TimeInterval
    if let lastTimestamp = directionCalibrationLastTimestamp {
      guard sample.timestamp > lastTimestamp else { return }
      elapsed = sample.timestamp - lastTimestamp
      if elapsed > 0.5 {
        resetDirectionCalibrationAttempt()
        directionCalibrationLastTimestamp = sample.timestamp
        calibrationProgress = 0
        liveGuidanceText = "跟踪曾中断，请重新做一次小幅\(directionMovementText)"
        return
      }
    } else {
      elapsed = 0
    }
    directionCalibrationLastTimestamp = sample.timestamp

    let filteredValue = directionCalibrationFilter.add(rawValue)
    let delta = filteredValue - axisCalibration.neutralDegrees
    let movementThreshold = max(
      axisCalibration.neutralBandDegrees + 1,
      currentExercise.defaultTargetDegrees * 0.55
    )
    let neutralThreshold = min(
      max(currentExercise.neutralBandDegrees, axisCalibration.neutralBandDegrees),
      currentExercise.defaultTargetDegrees * 0.5
    )

    switch directionCalibrationStage {
    case .seekingMovement:
      guard abs(delta) >= movementThreshold else {
        directionCalibrationSign = nil
        directionCalibrationMovementEvidence = 0
        directionCalibrationMovementSampleCount = 0
        calibrationProgress = 0
        return
      }

      let observedSign = delta < 0 ? -1.0 : 1.0
      if directionCalibrationSign == observedSign {
        directionCalibrationMovementSampleCount += 1
        directionCalibrationMovementEvidence += min(elapsed, 0.15)
        directionCalibrationPeakDegrees = max(
          directionCalibrationPeakDegrees,
          abs(delta)
        )
      } else {
        directionCalibrationSign = observedSign
        directionCalibrationMovementSampleCount = 1
        directionCalibrationMovementEvidence = 0
        directionCalibrationPeakDegrees = abs(delta)
      }
      calibrationProgress = min(
        0.5 * Double(directionCalibrationMovementSampleCount) / 3,
        0.5
      )
      guard directionCalibrationMovementSampleCount >= 3,
        directionCalibrationMovementEvidence >= 0.12
      else { return }

      directionCalibrationStage = .returningToNeutral
      directionCalibrationNeutralEvidence = 0
      directionCalibrationNeutralIsContinuous = false
      directionCalibrationFilter.reset()
      calibrationProgress = 0.55
      liveGuidanceText = "很好，现在缓慢回到正中并保持"

    case .returningToNeutral:
      guard abs(delta) <= neutralThreshold else {
        directionCalibrationNeutralEvidence = 0
        directionCalibrationNeutralIsContinuous = false
        return
      }
      if directionCalibrationNeutralIsContinuous {
        directionCalibrationNeutralEvidence += min(elapsed, 0.15)
      } else {
        directionCalibrationNeutralIsContinuous = true
      }
      calibrationProgress = min(
        0.55 + 0.45 * directionCalibrationNeutralEvidence / 0.3,
        1
      )
      guard directionCalibrationNeutralEvidence >= 0.3,
        let directionCalibrationSign
      else { return }

      applyLearnedDirectionSign(directionCalibrationSign)
      startCounterForCurrentExercise()
      phase = .exercising
      calibrationProgress = 1
      liveGuidanceText = "方向适配完成，请保持正中片刻"
    }
  }

  private func applyLearnedDirectionSign(_ learnedSign: Double) {
    guard let profile = calibrationProfile,
      let primaryDirection = currentExercise.directions.first
    else { return }

    let axes = profile.axes.map { axisCalibration in
      guard axisCalibration.axis == currentExercise.axis else { return axisCalibration }
      let directions = axisCalibration.directions.map { directionCalibration in
        let sign =
          directionCalibration.direction == primaryDirection
          ? learnedSign
          : -learnedSign
        let usesAdaptivePitchTarget = currentExercise.kind == .gentleNod
        let targetDegrees =
          usesAdaptivePitchTarget
          ? currentExercise.recognitionTargetDegrees(
            observedPeakDegrees: directionCalibrationPeakDegrees
          )
          : directionCalibration.targetDegrees
        let comfortablePeakDegrees =
          usesAdaptivePitchTarget
          ? max(directionCalibrationPeakDegrees, targetDegrees)
          : directionCalibration.comfortablePeakDegrees
        return DirectionCalibration(
          axis: directionCalibration.axis,
          direction: directionCalibration.direction,
          sign: sign,
          comfortablePeakDegrees: comfortablePeakDegrees,
          targetDegrees: targetDegrees
        )
      }
      return AxisCalibration(
        axis: axisCalibration.axis,
        neutralDegrees: axisCalibration.neutralDegrees,
        noiseMADDegrees: axisCalibration.noiseMADDegrees,
        neutralBandDegrees: axisCalibration.neutralBandDegrees,
        directions: directions
      )
    }
    calibrationProfile = CalibrationProfile(axes: axes)
  }

  private func resetDirectionCalibrationAttempt() {
    directionCalibrationStage = .seekingMovement
    directionCalibrationSign = nil
    directionCalibrationLastTimestamp = nil
    directionCalibrationMovementEvidence = 0
    directionCalibrationMovementSampleCount = 0
    directionCalibrationPeakDegrees = 0
    directionCalibrationNeutralEvidence = 0
    directionCalibrationNeutralIsContinuous = false
    directionCalibrationInvalidSince = nil
    directionCalibrationFilter.reset()
  }

  private func startCounterForCurrentExercise() {
    guard let calibrationProfile else { return }
    let configuration =
      currentExercise.kind == .gentleNod
      ? RepCounterConfiguration(
        maximumTargetHoldTrackingLossDuration: 1.2,
        allowsTargetHoldDuringTrackingLoss: true
      )
      : RepCounterConfiguration()
    repCounter = RepCounter(
      definition: currentExercise,
      calibration: calibrationProfile,
      configuration: configuration
    )
    currentRepetitions = 0
  }

  private func consumeExerciseSample(_ sample: MotionSample) {
    guard var counter = repCounter else { return }
    if sample.faceCount > 1 {
      counter.invalidateCurrentAttempt()
      repCounter = counter
      currentRepetitions = counter.completedRepetitions
      trackingWasLost = true
      liveGuidanceText = "检测到多人，计数已暂停"
      return
    }
    let event = counter.consume(sample)
    repCounter = counter
    currentRepetitions = counter.completedRepetitions

    switch event {
    case .none:
      trackingWasLost = false
      updateGuidance(for: counter.state, direction: counter.expectedDirection)
    case .stateChanged(let state):
      trackingWasLost = false
      updateGuidance(for: state, direction: counter.expectedDirection)
    case .repCompleted:
      trackingWasLost = false
      playCountFeedback()
      updateGuidance(for: counter.state, direction: counter.expectedDirection)
    case .finished:
      trackingWasLost = false
      playCountFeedback()
      completeCurrentExercise(mode: .camera)
    case .trackingLost:
      trackingWasLost = true
      if currentExercise.kind == .gentleNod,
        sample.faceCount <= 1,
        counter.state == .holdingTarget || counter.state == .returningToNeutral
      {
        liveGuidanceText = "低头时暂时没有看到完整脸部，请缓慢回正；重新看到中立位后继续判定"
      } else {
        liveGuidanceText =
          sample.faceCount > 1
          ? "检测到多人，计数已暂停"
          : "请保持脸部完整入镜，计数已暂停"
      }
    case .resetAfterTrackingLoss:
      trackingWasLost = true
      liveGuidanceText = "已失去跟踪，请回到中立位重新开始本次动作"
    }
  }

  private func invalidateCurrentAttempt() {
    guard var counter = repCounter else { return }
    counter.invalidateCurrentAttempt()
    repCounter = counter
  }

  private func updateGuidance(
    for state: RepCounterState,
    direction: MotionDirection?
  ) {
    switch state {
    case .awaitingNeutral:
      liveGuidanceText = "请回到中立位并保持"
    case .seekingTarget:
      if let direction {
        liveGuidanceText = "缓慢向\(direction.localizedName)移动"
      } else {
        liveGuidanceText = "缓慢完成动作"
      }
    case .holdingTarget:
      liveGuidanceText = "很好，轻轻保持"
    case .returningToNeutral:
      liveGuidanceText = "缓慢回到中立位"
    case .finished:
      liveGuidanceText = "动作完成"
    }
  }

  private func completeCurrentExercise(mode: CompletionMode) {
    guard phase == .exercising else { return }
    let result = ExerciseResult(
      exerciseID: currentExercise.kind,
      targetReps: currentExercise.targetRepetitions,
      completedReps: currentExercise.targetRepetitions,
      mode: mode
    )
    completedResults.append(result)

    guard currentExerciseIndex < plan.exercises.count - 1 else {
      finishWorkout()
      return
    }

    phase = .transitioning
    liveGuidanceText = "完成，准备下一个动作"
    let workItem = DispatchWorkItem { [weak self] in
      guard let self, self.phase == .transitioning else { return }
      self.currentExerciseIndex += 1
      self.currentRepetitions = 0
      if self.usesCamera {
        self.beginDirectionCalibrationForCurrentExercise()
      } else {
        self.phase = .exercising
        self.liveGuidanceText = "完成动作后点击“完成 1 次”"
      }
    }
    transitionWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
  }

  private func finishWorkout() {
    guard !savedSession else { return }
    savedSession = true
    phase = .completed
    cameraService.stop()

    let end = Date()
    let start = startedAt ?? end
    elapsedDuration = end.timeIntervalSince(start)
    let session = WorkoutSession(
      startedAt: start,
      endedAt: end,
      status: .completed,
      routineVersion: plan.routineVersion,
      results: completedResults,
      usedCamera: everUsedCamera
    )
    didSaveSession = appModel.saveCompletedSession(session)
  }

  private func handleCameraError(_ error: CameraCaptureError) {
    guard usesCamera, phase != .ready, phase != .completed else { return }
    if case .visionProcessingFailed = error {
      trackingWasLost = true
      liveGuidanceText = "识别暂时中断，正在重试…"
      return
    }

    invalidateCurrentAttempt()

    cameraErrorTitle = "无法使用摄像头"

    switch error {
    case .permissionDenied:
      cameraErrorMessage = "小桌伴没有摄像头权限。你可以前往系统设置授权，或继续使用手动计次。"
    case .permissionRestricted:
      cameraErrorMessage = "这台 Mac 限制了摄像头访问，可以继续使用手动计次。"
    case .noCameraAvailable:
      cameraErrorMessage = "没有找到可用摄像头，可以继续使用手动计次。"
    default:
      cameraErrorMessage = "摄像头暂时不可用：\(error.localizedDescription)"
    }
    isShowingCameraError = true
  }

  private func playCountFeedback() {
    guard appModel.settings.soundEnabled else { return }
    NSSound(named: NSSound.Name("Pop"))?.play()
  }
}
