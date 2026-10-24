import AppKit
import LinkWheelCore
import UserNotifications

/// Hands a picked link to its destination. On any failure nothing opens:
/// the user is told why and the URL goes to the clipboard so it is not lost.
enum Opener {
  static func open(_ url: URL, in destination: Destination) async {
    switch destination {
    case .safari:
      await openInSafari(url)
    case .dia(let profile):
      log.notice("opening in Dia profile \(profile.name, privacy: .public)")
      if let failure = await runDiaScript(url: url, profile: profile.name) {
        report(failure, url: url)
      }
    }
  }

  private static func openInSafari(_ url: URL) async {
    guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
      report(.scriptError("Safari is not installed"), url: url)
      return
    }
    do {
      _ = try await NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: .init())
    } catch {
      report(.scriptError(error.localizedDescription), url: url)
    }
  }

  /// Runs `osascript` with the URL and profile as arguments, off the main actor.
  /// Returns nil on success.
  @concurrent
  private static func runDiaScript(url: URL, profile: String) async -> OpenFailure? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/osascript")
    process.arguments = ["-e", DiaScript.source, url.absoluteString, profile]
    let stderr = Pipe()
    process.standardError = stderr
    process.standardOutput = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return .scriptError(error.localizedDescription)
    }
    // Backstop in case Dia hangs past the script's own timeout.
    let watchdog = Task {
      try await Task.sleep(for: .seconds(12))
      if process.isRunning { process.terminate() }
    }
    process.waitUntilExit()
    watchdog.cancel()

    log.notice("osascript exited \(process.terminationStatus, privacy: .public)")
    guard process.terminationStatus != 0 else { return nil }
    if process.terminationReason == .uncaughtSignal { return .timedOut }
    let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return OpenFailure.classify(stderr: message, profile: profile)
  }

  private static func report(_ failure: OpenFailure, url: URL) {
    log.error("open failed: \(failure.message, privacy: .public)")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)

    let content = UNMutableNotificationContent()
    content.title = "Link not opened"
    content.body = failure.message + " The link is on your clipboard."
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    )
  }
}
