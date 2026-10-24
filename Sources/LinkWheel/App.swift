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
  private let info = InfoWindowController()

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
    // A plain launch from Spotlight or Finder shows the info window; a link launch or a
    // login-item launch does not.
    let isPlainLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? false
    let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
      .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    log.notice("launch: plain \(isPlainLaunch, privacy: .public), at login \(launchedAtLogin, privacy: .public)")
    if isPlainLaunch && !launchedAtLogin { info.show() }

    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    // Start at login by default, once. After that the info window's toggle owns the setting.
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: "didEnableLoginItem") {
      do {
        try SMAppService.mainApp.register()
        defaults.set(true, forKey: "didEnableLoginItem")
      } catch {
        log.error("login item registration failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Opening LinkWheel again while it runs in the background (the usual case) shows the info window.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    info.show()
    return false
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
