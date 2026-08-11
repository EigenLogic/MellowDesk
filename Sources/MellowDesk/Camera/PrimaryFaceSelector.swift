import Foundation

struct FaceCandidate: Equatable {
  let sourceIndex: Int
  let confidence: Double
  let width: Double
  let height: Double

  var area: Double { width * height }
}

enum PrimaryFaceSelection: Equatable {
  case none
  case primary(sourceIndex: Int)
  case ambiguous(faceCount: Int)
}

struct PrimaryFaceSelector {
  let minimumConfidence: Double
  let minimumDimension: Double
  let ambiguousFaceAreaRatio: Double

  init(
    minimumConfidence: Double,
    minimumDimension: Double,
    ambiguousFaceAreaRatio: Double = 0.6
  ) {
    self.minimumConfidence = min(max(minimumConfidence, 0), 1)
    self.minimumDimension = min(max(minimumDimension, 0), 1)
    self.ambiguousFaceAreaRatio = min(max(ambiguousFaceAreaRatio, 0), 1)
  }

  func select(from candidates: [FaceCandidate]) -> PrimaryFaceSelection {
    let eligible =
      candidates
      .filter {
        $0.confidence.isFinite
          && $0.width.isFinite
          && $0.height.isFinite
          && $0.confidence >= minimumConfidence
          && $0.width >= minimumDimension
          && $0.height >= minimumDimension
      }
      .sorted {
        if $0.area == $1.area {
          return $0.sourceIndex < $1.sourceIndex
        }
        return $0.area > $1.area
      }

    guard let primary = eligible.first else { return .none }

    let ambiguityThreshold = primary.area * ambiguousFaceAreaRatio
    let competingFaceCount = eligible.prefix { $0.area >= ambiguityThreshold }.count
    if competingFaceCount > 1 {
      return .ambiguous(faceCount: competingFaceCount)
    }
    return .primary(sourceIndex: primary.sourceIndex)
  }
}
