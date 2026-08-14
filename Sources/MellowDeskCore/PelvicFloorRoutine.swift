import Foundation

/// One beat of a pelvic-floor follow-along cycle.
///
/// A cycle is a small repeating pattern (lift, hold, release, rest) that a segment
/// loops for its whole duration. Nothing here is measured; the routine is a paced
/// visual cue only.
public enum PelvicFloorPhase: String, CaseIterable, Codable, Hashable, Sendable {
  case lift
  case hold
  case release
  case rest

  /// Single character shown in the middle of the ring.
  public var glyph: String {
    switch self {
    case .lift: return "提"
    case .hold: return "住"
    case .release: return "放"
    case .rest: return "歇"
    }
  }

  public var localizedName: String {
    switch self {
    case .lift: return "向上收提"
    case .hold: return "保持"
    case .release: return "缓慢放松"
    case .rest: return "间歇"
    }
  }

  public var localizedCue: String {
    switch self {
    case .lift: return "像轻轻止住排气一样向内向上收提"
    case .hold: return "保持收提，正常呼吸"
    case .release: return "完全松开，不要突然放掉"
    case .rest: return "自然呼吸，等下一拍"
    }
  }
}

public struct PelvicFloorBeat: Equatable, Sendable {
  public let phase: PelvicFloorPhase
  public let duration: TimeInterval

  public init(phase: PelvicFloorPhase, duration: TimeInterval) {
    self.phase = phase
    self.duration = max(0.1, duration)
  }
}

/// A fixed-length block of the routine that repeats one tempo, such as slow lifts
/// or the short-short-long rhythm.
public struct PelvicFloorSegment: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let tempo: String
  public let coaching: String
  public let duration: TimeInterval
  public let cycle: [PelvicFloorBeat]

  public var cycleDuration: TimeInterval {
    cycle.reduce(0) { $0 + $1.duration }
  }

  /// Cycles are sized so a segment holds a whole number of them.
  public var cycleCount: Int {
    max(1, Int((duration / cycleDuration).rounded()))
  }

  public var liftsPerCycle: Int {
    cycle.filter { $0.phase == .lift }.count
  }

  public var liftCount: Int {
    liftsPerCycle * cycleCount
  }

  public init(
    id: String,
    title: String,
    tempo: String,
    coaching: String,
    duration: TimeInterval,
    cycle: [PelvicFloorBeat]
  ) {
    precondition(!cycle.isEmpty, "A segment needs at least one beat.")
    self.id = id
    self.title = title
    self.tempo = tempo
    self.coaching = coaching
    self.cycle = cycle
    self.duration = max(duration, cycle.reduce(0) { $0 + $1.duration })
  }
}

/// Everything the follow-along view needs to draw one frame.
public struct PelvicFloorRoutineState: Equatable, Sendable {
  public let elapsed: TimeInterval
  public let segmentIndex: Int
  public let segment: PelvicFloorSegment
  public let segmentElapsed: TimeInterval
  public let cycleIndex: Int
  public let beatIndex: Int
  public let beat: PelvicFloorBeat
  /// Progress inside the current beat, 0...1.
  public let phaseProgress: Double
  /// How contracted the ring is, 0...1: rises while lifting, stays in while holding,
  /// then returns to the relaxed position while releasing.
  public let ringProgress: Double
  public let completedLifts: Int
  public let segmentRemaining: TimeInterval
  public let totalRemaining: TimeInterval
  public let isFinished: Bool

  public var phase: PelvicFloorPhase { beat.phase }

  public var segmentProgress: Double {
    guard segment.duration > 0 else { return 0 }
    return min(max(segmentElapsed / segment.duration, 0), 1)
  }

  /// Stable identity of the current beat, useful as an animation trigger.
  public var beatID: String {
    "\(segmentIndex)-\(cycleIndex)-\(beatIndex)"
  }
}

/// The two-minute pelvic-floor (提肛) follow-along.
///
/// The routine is a paced cue, not a measurement: no camera, no sensor, and no
/// completion is recorded. Four half-minute segments change only the tempo.
public struct PelvicFloorRoutine: Equatable, Sendable {
  public let routineVersion: String
  public let displayName: String
  public let safetyNotice: String
  public let segments: [PelvicFloorSegment]

  public var totalDuration: TimeInterval {
    segments.reduce(0) { $0 + $1.duration }
  }

  public var totalLiftCount: Int {
    segments.reduce(0) { $0 + $1.liftCount }
  }

  public init(
    routineVersion: String,
    displayName: String,
    safetyNotice: String,
    segments: [PelvicFloorSegment]
  ) {
    precondition(!segments.isEmpty, "A routine needs at least one segment.")
    self.routineVersion = routineVersion
    self.displayName = displayName
    self.safetyNotice = safetyNotice
    self.segments = segments
  }

  /// Resolves the beat playing at `elapsed`. Out-of-range values clamp to the
  /// first and last frame, so a paused or overrun clock stays renderable.
  public func state(at elapsed: TimeInterval) -> PelvicFloorRoutineState {
    let total = totalDuration
    let clamped = min(max(elapsed, 0), total)

    var index = 0
    var segmentStart: TimeInterval = 0
    var liftsBefore = 0
    while index < segments.count - 1, clamped >= segmentStart + segments[index].duration {
      segmentStart += segments[index].duration
      liftsBefore += segments[index].liftCount
      index += 1
    }

    let segment = segments[index]
    let segmentElapsed = min(max(clamped - segmentStart, 0), segment.duration)

    if clamped >= total {
      return PelvicFloorRoutineState(
        elapsed: clamped,
        segmentIndex: index,
        segment: segment,
        segmentElapsed: segment.duration,
        cycleIndex: segment.cycleCount - 1,
        beatIndex: segment.cycle.count - 1,
        beat: segment.cycle[segment.cycle.count - 1],
        phaseProgress: 1,
        ringProgress: 0,
        completedLifts: totalLiftCount,
        segmentRemaining: 0,
        totalRemaining: 0,
        isFinished: true
      )
    }

    let cycleIndex = min(Int(segmentElapsed / segment.cycleDuration), segment.cycleCount - 1)
    var beatOffset = segmentElapsed - Double(cycleIndex) * segment.cycleDuration
    var beatIndex = segment.cycle.count - 1
    var liftsThisCycle = 0
    for (offsetIndex, beat) in segment.cycle.enumerated() {
      if beatOffset < beat.duration || offsetIndex == segment.cycle.count - 1 {
        beatIndex = offsetIndex
        break
      }
      if beat.phase == .lift {
        liftsThisCycle += 1
      }
      beatOffset -= beat.duration
    }

    let beat = segment.cycle[beatIndex]
    let phaseProgress = min(max(beatOffset / beat.duration, 0), 1)

    return PelvicFloorRoutineState(
      elapsed: clamped,
      segmentIndex: index,
      segment: segment,
      segmentElapsed: segmentElapsed,
      cycleIndex: cycleIndex,
      beatIndex: beatIndex,
      beat: beat,
      phaseProgress: phaseProgress,
      ringProgress: Self.ringProgress(phase: beat.phase, phaseProgress: phaseProgress),
      completedLifts: liftsBefore + cycleIndex * segment.liftsPerCycle + liftsThisCycle,
      segmentRemaining: segment.duration - segmentElapsed,
      totalRemaining: total - clamped,
      isFinished: false
    )
  }

  private static func ringProgress(phase: PelvicFloorPhase, phaseProgress: Double) -> Double {
    switch phase {
    case .lift: return phaseProgress
    case .hold: return 1
    case .release: return 1 - phaseProgress
    case .rest: return 0
    }
  }

  public static let v1 = PelvicFloorRoutine(
    routineVersion: "pelvic-floor-v1.0",
    displayName: "提肛跟练",
    safetyNotice:
      "全程自然呼吸，不憋气，也不要同时收紧腹部、臀部或大腿。出现疼痛、明显不适或原有症状加重请立即停止，并咨询专业人士；本练习不替代医疗诊断或治疗。",
    segments: [
      PelvicFloorSegment(
        id: "slow",
        title: "慢速提肛",
        tempo: "3 秒提 · 2 秒保持 · 3 秒放 · 2 秒歇",
        coaching: "慢慢向上收提，保持两秒，再用三秒完全松开。",
        duration: 30,
        cycle: [
          PelvicFloorBeat(phase: .lift, duration: 3),
          PelvicFloorBeat(phase: .hold, duration: 2),
          PelvicFloorBeat(phase: .release, duration: 3),
          PelvicFloorBeat(phase: .rest, duration: 2),
        ]
      ),
      PelvicFloorSegment(
        id: "fast",
        title: "快速提肛",
        tempo: "1 秒提 · 1 秒放",
        coaching: "幅度小一点、频率快一点，跟着圆环一提一放。",
        duration: 30,
        cycle: [
          PelvicFloorBeat(phase: .lift, duration: 1),
          PelvicFloorBeat(phase: .release, duration: 1),
        ]
      ),
      PelvicFloorSegment(
        id: "rock",
        title: "快快慢",
        tempo: "快 · 快 · 慢（节奏像 We Will Rock You）",
        coaching: "两下短提，接一下长提并保持，然后完整放松一拍。",
        duration: 30,
        cycle: [
          PelvicFloorBeat(phase: .lift, duration: 0.5),
          PelvicFloorBeat(phase: .release, duration: 0.5),
          PelvicFloorBeat(phase: .lift, duration: 0.5),
          PelvicFloorBeat(phase: .release, duration: 0.5),
          PelvicFloorBeat(phase: .lift, duration: 1),
          PelvicFloorBeat(phase: .hold, duration: 1),
          PelvicFloorBeat(phase: .release, duration: 1),
          PelvicFloorBeat(phase: .rest, duration: 1),
        ]
      ),
      PelvicFloorSegment(
        id: "quickLiftSlowRelease",
        title: "快提慢放",
        tempo: "快提 · 1.5 秒保持 · 3 秒慢放",
        coaching: "一下提到位，保持住，再用三秒慢慢放下。",
        duration: 30,
        cycle: [
          PelvicFloorBeat(phase: .lift, duration: 0.5),
          PelvicFloorBeat(phase: .hold, duration: 1.5),
          PelvicFloorBeat(phase: .release, duration: 3),
          PelvicFloorBeat(phase: .rest, duration: 1),
        ]
      ),
    ]
  )
}
