import AppKit
import LinkWheelCore
import SwiftUI

@Observable
final class WheelModel {
  var url: URL?
  var destinations: [Destination] = []
  var hovered: Int?
  var visible = false
  var onPick: (Int) -> Void = { _ in }
  var onCancel: () -> Void = {}

  func appear() {
    visible = false
    withAnimation(.spring(duration: 0.22, bounce: 0.22)) { visible = true }
  }
}

/// Logos: a custom image in ~/Library/Application Support/LinkWheel/Logos/<profile name>.png wins;
/// otherwise a monogram in the profile's Dia colour. Safari and Dia use their real app icons.
@MainActor
enum Logos {
  static let customDirectory = URL.applicationSupportDirectory.appending(path: "LinkWheel/Logos")

  private static var cache: [String: NSImage] = [:]

  static func custom(for profile: DiaProfile) -> NSImage? {
    for ext in ["png", "jpg", "jpeg", "heic"] {
      let url = customDirectory.appending(path: "\(profile.name).\(ext)")
      if let image = NSImage(contentsOf: url) { return image }
    }
    return nil
  }

  static func appIcon(bundleID: String) -> NSImage? {
    if let cached = cache[bundleID] { return cached }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    cache[bundleID] = icon
    return icon
  }
}

struct WheelView: View {
  let model: WheelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let ringRadius: Double = 112
  private let hubRadius: Double = 52
  private let outerRadius: Double = 168
  private let orbSize: Double = 62

  private var geometry: WheelGeometry {
    WheelGeometry(count: model.destinations.count, innerRadius: hubRadius, outerRadius: outerRadius)
  }

  var body: some View {
    GeometryReader { proxy in
      let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
      ZStack {
        backdrop
        if let hovered = model.hovered {
          highlight(for: hovered)
        }
        ForEach(Array(model.destinations.enumerated()), id: \.offset) { index, destination in
          item(index: index, destination: destination)
            .position(position(of: index, centre: centre, visible: model.visible))
        }
        hub
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .contentShape(Circle())
      .onContinuousHover(coordinateSpace: .local) { phase in
        switch phase {
        case .active(let point):
          let wedge = geometry.wedge(atX: point.x - centre.x, y: point.y - centre.y)
          if wedge != model.hovered {
            withAnimation(.easeOut(duration: 0.12)) { model.hovered = wedge }
          }
        case .ended:
          withAnimation(.easeOut(duration: 0.12)) { model.hovered = nil }
        }
      }
      .gesture(SpatialTapGesture().onEnded { tap in
        if let index = geometry.wedge(atX: tap.location.x - centre.x, y: tap.location.y - centre.y) {
          model.onPick(index)
        } else {
          model.onCancel()  // the hub cancels
        }
      })
    }
    .scaleEffect(model.visible || reduceMotion ? 1 : 0.9)
    .opacity(model.visible ? 1 : 0)
    .environment(\.colorScheme, .dark)  // one dark look, readable over light and dark windows
  }

  /// Items start at the centre and spring out to the ring.
  private func position(of index: Int, centre: CGPoint, visible: Bool) -> CGPoint {
    let radius = visible || reduceMotion ? Self.ringRadius : 24
    let offset = geometry.labelOffset(of: index, radius: radius)
    return CGPoint(x: centre.x + offset.x, y: centre.y + offset.y)
  }

  private var backdrop: some View {
    Circle()
      .fill(.regularMaterial)
      .overlay(Circle().fill(Color.black.opacity(0.28)))  // keeps text readable over busy windows
      .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
      .frame(width: outerRadius * 2, height: outerRadius * 2)
      .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
  }

  private func highlight(for index: Int) -> some View {
    WedgeShape(range: geometry.angleRange(of: index), inner: hubRadius + 4, outer: outerRadius - 4, gap: 0.02)
      .fill(accent(of: model.destinations[index]).opacity(0.28))
      .frame(width: outerRadius * 2, height: outerRadius * 2)
      .transition(.opacity)
  }

  private func item(index: Int, destination: Destination) -> some View {
    let isHovered = model.hovered == index
    return VStack(spacing: 6) {
      ZStack(alignment: .topTrailing) {
        LogoView(destination: destination, size: orbSize)
          .shadow(color: accent(of: destination).opacity(isHovered ? 0.7 : 0), radius: 12)
        Text("\(index + 1)")
          .font(.system(size: 10, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .frame(width: 18, height: 18)
          .background(Circle().fill(.black.opacity(0.55)))
          .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
          .offset(x: 4, y: -4)
      }
      Text(destination.title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .frame(maxWidth: 92)
        .shadow(color: .black.opacity(0.5), radius: 2)
    }
    .scaleEffect(isHovered ? 1.1 : 1)
    .animation(.spring(duration: 0.18, bounce: 0.3), value: isHovered)
    .animation(
      reduceMotion ? nil : .spring(duration: 0.28, bounce: 0.28).delay(Double(index) * 0.02),
      value: model.visible
    )
  }

  private var hub: some View {
    let shown: (host: String, path: String) =
      if let url = model.url { displayString(for: url) } else { (host: "", path: "") }
    return VStack(spacing: 3) {
      Text(shown.host)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
      if !shown.path.isEmpty {
        Text(shown.path)
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .foregroundStyle(.white.opacity(0.7))
      }
      Text("esc to cancel")
        .font(.system(size: 8))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.top, 2)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .padding(12)
    .frame(width: hubRadius * 2, height: hubRadius * 2)
    .background(Circle().fill(.black.opacity(0.32)))
    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
  }

  private func accent(of destination: Destination) -> Color {
    switch destination {
    case .dia(let profile): profile.swiftUIColor
    case .safari: .blue
    }
  }
}

struct LogoView: View {
  let destination: Destination
  let size: Double

  var body: some View {
    switch destination {
    case .safari:
      appIcon("com.apple.Safari")
    case .dia(let profile):
      ZStack(alignment: .bottomTrailing) {
        if let custom = Logos.custom(for: profile) {
          Image(nsImage: custom)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
          monogram(profile)
        }
        if let dia = Logos.appIcon(bundleID: "company.thebrowser.dia") {
          Image(nsImage: dia)
            .resizable()
            .frame(width: size * 0.36, height: size * 0.36)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .offset(x: 3, y: 3)
        }
      }
    }
  }

  private func monogram(_ profile: DiaProfile) -> some View {
    let colour = profile.swiftUIColor
    return Circle()
      .fill(LinearGradient(colors: [colour.mix(with: .white, by: 0.25), colour], startPoint: .top, endPoint: .bottom))
      .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
      .overlay(
        Text(profile.initial)
          .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
          .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
      )
      .frame(width: size, height: size)
  }

  @ViewBuilder
  private func appIcon(_ bundleID: String) -> some View {
    if let icon = Logos.appIcon(bundleID: bundleID) {
      Image(nsImage: icon).resizable().frame(width: size * 1.08, height: size * 1.08)
    } else {
      Circle().fill(.blue).frame(width: size, height: size)
    }
  }
}

extension DiaProfile {
  var swiftUIColor: Color {
    guard let rgb else { return .gray }
    return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
  }
}

/// An annular sector. Angles are clockwise from 12 o'clock, matching `WheelGeometry`.
nonisolated struct WedgeShape: Shape {  // SwiftUI calls path(in:) off the main thread
  var range: ClosedRange<Double>
  var inner: Double
  var outer: Double
  var gap: Double

  func path(in rect: CGRect) -> Path {
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    // SwiftUI angles start at 3 o'clock; shift by -90° to start at 12.
    let start = Angle(radians: range.lowerBound + gap - .pi / 2)
    let end = Angle(radians: range.upperBound - gap - .pi / 2)
    var path = Path()
    path.addArc(center: centre, radius: outer, startAngle: start, endAngle: end, clockwise: false)
    path.addArc(center: centre, radius: inner, startAngle: end, endAngle: start, clockwise: true)
    path.closeSubpath()
    return path
  }
}
