import AppKit
import LinkWheelCore
import SwiftUI

/// A borderless panel that can take keyboard focus without activating LinkWheel,
/// so the app you clicked the link in stays in front.
private final class WheelPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

/// Owns the one wheel on screen. A new link while it is open replaces the URL; wheels never stack.
final class WheelController {
  static let diameter: CGFloat = 440  // disc is 336; the rest is room for its shadow

  private let model = WheelModel()
  private var panel: WheelPanel?
  private var outsideClickMonitor: Any?
  private var keyMonitor: Any?

  func present(url: URL, destinations: [Destination]) {
    model.url = url
    model.destinations = destinations
    model.hovered = nil
    model.onPick = { [weak self] index in self?.pick(index) }
    model.onCancel = { [weak self] in self?.dismiss(reason: "hub tap") }

    let panel = self.panel ?? makePanel()
    self.panel = panel
    panel.setFrame(frameCentredOnCursor(), display: true)
    panel.orderFrontRegardless()
    panel.makeKey()
    model.appear()
    installMonitors()
    log.notice("presented, panel key: \(panel.isKeyWindow, privacy: .public)")
  }

  private func makePanel() -> WheelPanel {
    let panel = WheelPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.contentView = NSHostingView(rootView: WheelView(model: model))
    return panel
  }

  /// Centred on the cursor, nudged inside the visible frame of whichever display the cursor is on.
  private func frameCentredOnCursor() -> NSRect {
    let mouse = NSEvent.mouseLocation
    let size = Self.diameter
    var frame = NSRect(x: mouse.x - size / 2, y: mouse.y - size / 2, width: size, height: size)
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - size)
      frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - size)
    }
    return frame
  }

  private func installMonitors() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      log.notice("key \(event.keyCode, privacy: .public)")
      if event.keyCode == 53 {  // Esc
        dismiss(reason: "esc")
      } else if let index = wedgeIndex(forKey: event.charactersIgnoringModifiers ?? "",
                                       count: model.destinations.count) {
        pick(index)
      }
      return nil
    }
    // Clicks in other apps never reach a local monitor; a global one sees them.
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss(reason: "outside click") }
    }
  }

  private func removeMonitors() {
    [keyMonitor, outsideClickMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
    keyMonitor = nil
    outsideClickMonitor = nil
  }

  private func pick(_ index: Int) {
    guard model.destinations.indices.contains(index), let url = model.url else { return }
    let destination = model.destinations[index]
    log.notice("picked \(destination.title, privacy: .public)")
    dismiss(reason: "picked")
    Task { await Opener.open(url, in: destination) }
  }

  /// Cancel drops the link: nothing opens.
  private func dismiss(reason: String) {
    log.notice("dismiss: \(reason, privacy: .public)")
    removeMonitors()
    panel?.orderOut(nil)
    model.url = nil
  }
}
