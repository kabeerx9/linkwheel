import AppKit
import LinkWheelCore
import ServiceManagement
import UserNotifications
import os

nonisolated let log = Logger(subsystem: "dev.kabeer.LinkWheel", category: "app")

@main
struct LinkWheelMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // no Dock icon, no menu bar
    app.run()
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let wheel = WheelController()

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Registered before launch finishes so a link that cold-launched the app is not missed.
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleGetURL(_:withReply:)),
      forEventClass: AEEventClass(kInternetEventClass),
      andEventID: AEEventID(kAEGetURL)
    )
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    do {
      try SMAppService.mainApp.register()  // stay resident: start at login
    } catch {
      log.error("login item registration failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Local HTML files opened with LinkWheel arrive here rather than as a GetURL event.
  func application(_ application: NSApplication, open urls: [URL]) {
    urls.forEach(route)
  }

  @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
    guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
          let url = URL(string: string)
    else { return }
    route(url)
  }

  private func route(_ url: URL) {
    guard isRoutable(url) else {
      log.notice("refused non-web URL scheme \(url.scheme ?? "-", privacy: .public)")
      return
    }
    wheel.present(url: url, destinations: destinations(diaProfiles: DiaProfiles.load()))
  }
}
