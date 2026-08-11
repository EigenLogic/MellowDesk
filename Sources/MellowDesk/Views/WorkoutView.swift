import MellowDeskCore
import SwiftUI

struct WorkoutView: View {
  @StateObject private var viewModel: WorkoutViewModel

  init(viewModel: WorkoutViewModel) {
    _viewModel = StateObject(wrappedValue: viewModel)
  }

  var body: some View {
    ZStack {
      AppTheme.warmBackground.opacity(0.58)
        .ignoresSafeArea()

      switch viewModel.phase {
      case .ready:
        readyView
      case .calibrating, .calibratingDirection, .exercising, .transitioning:
        activeWorkoutView
      case .completed:
        completedView
      }
    }
    .frame(minWidth: 860, minHeight: 620)
    .alert(
      viewModel.cameraErrorTitle,
      isPresented: $viewModel.isShowingCameraError
    ) {
      Button("改用手动计次") { viewModel.useManualMode() }
      Button("打开系统设置") { viewModel.openCameraSettings() }
      Button("取消", role: .cancel) {}
    } message: {
      Text(viewModel.cameraErrorMessage ?? "可以继续跟随动画，并手动确认每次动作。")
    }
  }

  private var readyView: some View {
    HStack(spacing: 34) {
      ExerciseAnimationView(kind: .rotation)
        .frame(maxWidth: 430)

      VStack(alignment: .leading, spacing: 20) {
        PillLabel(systemImage: "clock", text: "约 3 分钟")

        VStack(alignment: .leading, spacing: 8) {
          Text("准备好，一起活动颈肩")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.ink)
          Text("动画会演示动作，前置摄像头只在本次训练中开启，并自动记录完成次数。")
            .font(.title3)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 11) {
          ForEach(Array(viewModel.plan.exercises.enumerated()), id: \.element.id) {
            index, exercise in
            HStack(spacing: 11) {
              Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 25, height: 25)
                .background(AppTheme.accent, in: Circle())
              VStack(alignment: .leading, spacing: 1) {
                Text(exercise.displayName)
                  .font(.subheadline.weight(.semibold))
                Text(exerciseDose(exercise))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        Text("请在舒适范围内缓慢完成；如果动作引起疼痛或眩晕，请立即停止。")
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(11)
          .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

        HStack {
          Button("暂不开始") {
            AppWindowCoordinator.shared.closeWorkout()
          }
          Spacer()
          Button {
            viewModel.begin()
          } label: {
            Label("开启摄像头并开始", systemImage: "camera.fill")
          }
          .buttonStyle(.borderedProminent)
          .tint(AppTheme.accent)
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
        }
      }
      .frame(width: 410)
    }
    .padding(38)
  }

  private var activeWorkoutView: some View {
    VStack(spacing: 18) {
      workoutHeader

      HStack(alignment: .top, spacing: 18) {
        guidancePanel
        cameraPanel
      }
      .frame(maxHeight: .infinity)

      workoutControls
    }
    .padding(26)
  }

  private var workoutHeader: some View {
    HStack(spacing: 15) {
      ForEach(Array(viewModel.plan.exercises.enumerated()), id: \.element.id) { index, exercise in
        HStack(spacing: 8) {
          ZStack {
            Circle()
              .fill(stepColor(index))
              .frame(width: 27, height: 27)
            if index < viewModel.currentExerciseIndex {
              Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
            } else {
              Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(index == viewModel.currentExerciseIndex ? .white : .secondary)
            }
          }
          Text(exercise.displayName)
            .font(
              .subheadline.weight(index == viewModel.currentExerciseIndex ? .semibold : .regular)
            )
            .foregroundStyle(index <= viewModel.currentExerciseIndex ? .primary : .secondary)
        }

        if index < viewModel.plan.exercises.count - 1 {
          Rectangle()
            .fill(
              index < viewModel.currentExerciseIndex ? AppTheme.accent : Color.primary.opacity(0.12)
            )
            .frame(height: 2)
        }
      }
    }
  }

  private var guidancePanel: some View {
    VStack(alignment: .leading, spacing: 15) {
      ExerciseAnimationView(
        kind: viewModel.currentAnimationKind,
        isPlaying: !viewModel.isPaused,
        directionSign: viewModel.animationDirectionSign
      )

      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 4) {
          Text(viewModel.currentExercise.displayName)
            .font(.title2.weight(.bold))
            .foregroundStyle(AppTheme.ink)
          Text(viewModel.instructionText)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        CompletionRing(
          progress: viewModel.exerciseProgress,
          completed: viewModel.currentRepetitions,
          target: viewModel.currentExercise.targetRepetitions,
          size: 92
        )
      }

      Text(viewModel.currentExercise.safetyBoundary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
    .appCard()
    .frame(maxWidth: .infinity)
  }

  private var cameraPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(viewModel.usesCamera ? "摄像头识别" : "手动计次")
          .font(.headline)
        Spacer()
        PillLabel(
          systemImage: viewModel.trackingStatusIcon,
          text: viewModel.trackingStatusText,
          color: viewModel.trackingStatusColor
        )
      }

      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color.black.opacity(0.88))

        if viewModel.usesCamera {
          CameraPreviewView(session: viewModel.cameraService.captureSession)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
          VStack(spacing: 13) {
            Image(systemName: "person.crop.rectangle.badge.plus")
              .font(.system(size: 39))
            Text("跟随左侧动画完成动作")
              .font(.headline)
            Text("每次回到中立位后，点击下方按钮。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .foregroundStyle(.white)
        }

        if viewModel.phase == .calibrating {
          VStack(spacing: 12) {
            ProgressView(value: viewModel.calibrationProgress)
              .frame(width: 180)
            Text("保持正脸和肩膀放松")
              .font(.headline)
            Text("正在校准中立位…")
              .font(.caption)
          }
          .foregroundStyle(.white)
          .padding(22)
          .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        }

        if viewModel.phase == .calibratingDirection {
          VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
              .font(.title2)
            ProgressView(value: viewModel.calibrationProgress)
              .frame(width: 180)
            Text("适配本动作的摄像头方向")
              .font(.headline)
            Text(viewModel.liveGuidanceText)
              .font(.caption)
              .multilineTextAlignment(.center)
          }
          .foregroundStyle(.white)
          .padding(22)
          .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        }

        if viewModel.isPaused {
          VStack(spacing: 10) {
            Image(systemName: "pause.fill")
              .font(.title)
            Text("训练已暂停")
              .font(.headline)
          }
          .foregroundStyle(.white)
          .padding(24)
          .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 16))
        }
      }
      .aspectRatio(4 / 3, contentMode: .fit)

      Text(viewModel.liveGuidanceText)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(viewModel.liveGuidanceColor)
        .frame(maxWidth: .infinity, minHeight: 30)

      if !viewModel.usesCamera {
        Button {
          viewModel.recordManualRepetition()
        } label: {
          Label("完成 1 次", systemImage: "plus.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
        .controlSize(.large)
        .disabled(viewModel.phase != .exercising || viewModel.isPaused)
      }
    }
    .appCard()
    .frame(width: 390)
  }

  private var workoutControls: some View {
    HStack {
      Button("结束本次") {
        AppWindowCoordinator.shared.closeWorkout()
      }

      if viewModel.usesCamera, viewModel.phase != .transitioning {
        Button("改用手动计次") {
          viewModel.useManualMode()
        }
      }

      Spacer()

      if viewModel.usesCamera, viewModel.phase == .exercising {
        Button("重新校准") {
          viewModel.recalibrate()
        }
      }

      Button(viewModel.isPaused ? "继续" : "暂停") {
        viewModel.togglePause()
      }
      .disabled(viewModel.phase != .exercising)
    }
  }

  private var completedView: some View {
    VStack(spacing: 23) {
      ZStack {
        Circle()
          .fill(AppTheme.accentSoft)
          .frame(width: 112, height: 112)
        Image(systemName: "checkmark")
          .font(.system(size: 48, weight: .bold))
          .foregroundStyle(AppTheme.accent)
      }

      VStack(spacing: 7) {
        Text("完成了，很好")
          .font(.system(size: 31, weight: .bold, design: .rounded))
          .foregroundStyle(AppTheme.ink)
        Text(completionSummary)
          .font(.title3)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 13) {
        ForEach(viewModel.completedResults, id: \.exerciseID) { result in
          VStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(AppTheme.accent)
            Text(viewModel.name(for: result.exerciseID))
              .font(.subheadline.weight(.semibold))
            Text("\(result.completedReps)/\(result.targetReps) 次")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(width: 175, height: 92)
          .appCard(padding: 12)
        }
      }

      HStack {
        Button("查看完成记录") {
          AppWindowCoordinator.shared.showDashboard()
          AppWindowCoordinator.shared.closeWorkout()
        }
        Button("完成") {
          AppWindowCoordinator.shared.closeWorkout()
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(40)
  }

  private func exerciseDose(_ exercise: ExerciseDefinition) -> String {
    if exercise.isBilateral {
      return "每侧 \(exercise.repetitionsPerDirection) 次"
    }
    return "\(exercise.repetitionsPerDirection) 次"
  }

  private var completionSummary: String {
    let duration = AppFormatters.duration(seconds: viewModel.elapsedDuration)
    return viewModel.didSaveSession
      ? "本次用时 \(duration)，已记录在本机。"
      : "本次用时 \(duration)，但本地记录保存失败。"
  }

  private func stepColor(_ index: Int) -> Color {
    index <= viewModel.currentExerciseIndex ? AppTheme.accent : Color.primary.opacity(0.10)
  }
}
