import Foundation

/// Layout and hit-testing for a ring of `count` equal wedges around a centre point.
/// Angles are in radians, clockwise from 12 o'clock, in a y-down coordinate space (SwiftUI).
public struct WheelGeometry: Equatable, Sendable {
  public var count: Int
  public var innerRadius: Double
  public var outerRadius: Double

  public init(count: Int, innerRadius: Double, outerRadius: Double) {
    precondition(innerRadius >= 0 && outerRadius > innerRadius, "invalid wheel radii")
    self.count = count
    self.innerRadius = innerRadius
    self.outerRadius = outerRadius
  }

  public var wedgeAngle: Double { count > 0 ? 2 * .pi / Double(count) : 0 }

  /// Wedge `index` is centred on its angle, so wedge 0 sits straight up.
  public func angleRange(of index: Int) -> ClosedRange<Double> {
    let mid = Double(index) * wedgeAngle
    return (mid - wedgeAngle / 2)...(mid + wedgeAngle / 2)
  }

  /// Point at `radius` along the centre line of wedge `index`, relative to the centre.
  public func labelOffset(of index: Int, radius: Double) -> (x: Double, y: Double) {
    let angle = Double(index) * wedgeAngle
    return (sin(angle) * radius, -cos(angle) * radius)
  }

  /// The wedge under a point given relative to the centre, or nil in the hub or outside the ring.
  public func wedge(atX dx: Double, y dy: Double) -> Int? {
    guard count > 0 else { return nil }
    let distance = (dx * dx + dy * dy).squareRoot()
    guard distance >= innerRadius, distance <= outerRadius else { return nil }
    var angle = atan2(dx, -dy)  // 0 at 12 o'clock, growing clockwise
    angle += wedgeAngle / 2  // shift so each wedge's range starts at 0
    if angle < 0 { angle += 2 * .pi }
    return Int(angle / wedgeAngle) % count
  }
}

/// "1"..."9" select a wedge; anything else is not a selection.
public func wedgeIndex(forKey characters: String, count: Int) -> Int? {
  guard let digit = Int(characters), (1...min(count, 9)).contains(digit) else { return nil }
  return digit - 1
}
