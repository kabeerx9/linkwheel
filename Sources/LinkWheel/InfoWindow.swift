import AppKit
import LinkWheelCore
import ServiceManagement
import SwiftUI

/// The small window shown when LinkWheel is opened directly (Spotlight, Finder) rather than by a link.
final class InfoWindowController {
  private var window: NSWindow?

  func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    window.contentView = NSHostingView(rootView: InfoView(onClose: { [weak window] in window?.close() }))
    window.center()
    // macOS may refuse activation during launch; ordering front regardless keeps the window visible.
    NSApp.activate()
    window.orderFrontRegardless()
    window.makeKey()
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 10),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    return window
  }
}

struct InfoView: View {
  let onClose: () -> Void

  @State private var isDefault = InfoView.isDefaultBrowser()
  @State private var startsAtLogin = SMAppService.mainApp.status == .enabled
  private let profiles = DiaProfiles.load()
  private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "circle.circle.fill")
          .font(.system(size: 26))
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 1) {
          Text("LinkWheel").font(.headline)
          Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        status(isDefault ? "Default browser" : "Not the default browser", ok: isDefault)
        status(profiles.isEmpty ? "No Dia profiles found" : "\(profiles.count) Dia profiles", ok: !profiles.isEmpty)
        if !profiles.isEmpty {
          HStack(spacing: 6) {
            ForEach(profiles, id: \.folder) { profile in
              Text(profile.name)
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(profile.swiftUIColor.opacity(0.25)))
            }
          }
          .padding(.leading, 20)
        }
      }

      Text("Click any link → pick with the mouse or 1–9. Esc drops the link.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Divider()

      Toggle("Start at login", isOn: $startsAtLogin)
        .toggleStyle(.switch)
        .controlSize(.small)
        .onChange(of: startsAtLogin) { _, enabled in
          do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
          } catch {
            startsAtLogin = SMAppService.mainApp.status == .enabled
          }
        }

      HStack {
        if !isDefault {
          Button("Make Default") {
            Task {
              try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
              isDefault = InfoView.isDefaultBrowser()
            }
          }
        }
        Spacer()
        Button("Quit") { NSApp.terminate(nil) }
        Button("Done", action: onClose).keyboardShortcut(.defaultAction)
      }
    }
    .padding(18)
    .padding(.top, 6)
    .frame(width: 300)
  }

  private func status(_ text: String, ok: Bool) -> some View {
    Label {
      Text(text).font(.callout)
    } icon: {
      Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        .foregroundStyle(ok ? .green : .orange)
    }
  }

  static func isDefaultBrowser() -> Bool {
    guard let url = URL(string: "https://example.com"),
          let handler = NSWorkspace.shared.urlForApplication(toOpen: url)
    else { return false }
    return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
  }
}
