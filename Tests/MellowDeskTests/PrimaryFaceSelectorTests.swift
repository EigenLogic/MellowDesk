import XCTest

@testable import MellowDesk

final class PrimaryFaceSelectorTests: XCTestCase {
  private let selector = PrimaryFaceSelector(
    minimumConfidence: 0.25,
    minimumDimension: 0.08,
    ambiguousFaceAreaRatio: 0.6
  )

  func testFiltersSmallAndLowConfidenceCandidates() {
    XCTAssertEqual(
      selector.select(from: [
        candidate(0, confidence: 0.9, width: 0.4, height: 0.4),
        candidate(1, confidence: 0.2, width: 0.4, height: 0.4),
        candidate(2, confidence: 0.9, width: 0.07, height: 0.4),
      ]),
      .primary(sourceIndex: 0)
    )
  }

  func testIgnoresClearlySmallerBackgroundFace() {
    XCTAssertEqual(
      selector.select(from: [
        candidate(4, width: 0.5, height: 0.5),
        candidate(7, width: 0.3, height: 0.3),
      ]),
      .primary(sourceIndex: 4)
    )
  }

  func testAreaRatioBoundaryIsDeterministic() {
    XCTAssertEqual(
      selector.select(from: [
        candidate(0, width: 1, height: 1),
        candidate(1, width: 0.5999, height: 1),
      ]),
      .primary(sourceIndex: 0)
    )
    XCTAssertEqual(
      selector.select(from: [
        candidate(0, width: 1, height: 1),
        candidate(1, width: 0.6, height: 1),
      ]),
      .ambiguous(faceCount: 2)
    )
  }

  func testCountsOnlySimilarlySizedCompetitorsRegardlessOfInputOrder() {
    let candidates = [
      candidate(9, width: 0.4, height: 0.4),
      candidate(3, width: 0.5, height: 0.5),
      candidate(6, width: 0.39, height: 0.4),
      candidate(1, width: 0.1, height: 0.1),
    ]

    XCTAssertEqual(selector.select(from: candidates), .ambiguous(faceCount: 3))
    XCTAssertEqual(selector.select(from: Array(candidates.reversed())), .ambiguous(faceCount: 3))
  }

  func testReturnsNoneWhenNoCandidateIsEligible() {
    XCTAssertEqual(
      selector.select(from: [candidate(0, confidence: 0.1, width: 0.5, height: 0.5)]),
      .none
    )
  }

  private func candidate(
    _ sourceIndex: Int,
    confidence: Double = 0.9,
    width: Double,
    height: Double
  ) -> FaceCandidate {
    FaceCandidate(
      sourceIndex: sourceIndex,
      confidence: confidence,
      width: width,
      height: height
    )
  }
}
