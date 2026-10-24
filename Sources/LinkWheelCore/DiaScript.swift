import Foundation

/// The AppleScript that opens a URL in a named Dia profile.
/// URL and profile name arrive as `argv`, never interpolated into source,
/// so a link containing quotes cannot inject script.
public enum DiaScript {
  public static let profileNotFoundCode = 9001

  public static let source = """
    on run argv
      set theURL to item 1 of argv
      set profileName to item 2 of argv
      with timeout of 8 seconds
        tell application "Dia"
          -- Dia may still be restoring windows right after launch.
          repeat 20 times
            if (count of windows) > 0 then exit repeat
            delay 0.1
          end repeat
          if (count of windows) = 0 then make new window
          set w to window 1
          set matches to (every profile of w whose name is profileName)
          if (count of matches) = 0 then error "Profile not found" number \(profileNotFoundCode)
          set p to item 1 of matches
          focus p
          make new tab at p with properties {URL:theURL}
          activate
        end tell
      end timeout
    end run
    """
}

/// Why a Dia open failed. Every case means nothing was opened.
public enum OpenFailure: Error, Equatable, Sendable {
  case automationDenied
  case profileNotFound(String)
  case timedOut
  case scriptError(String)

  public var message: String {
    switch self {
    case .automationDenied:
      "LinkWheel isn't allowed to control Dia. Allow it in System Settings → Privacy & Security → Automation."
    case .profileNotFound(let name):
      "Dia has no profile named “\(name)”."
    case .timedOut:
      "Dia didn't respond in time."
    case .scriptError(let detail):
      "Dia couldn't open the link: \(detail)"
    }
  }

  /// Classifies `osascript` stderr, which ends with the AppleScript error number in parentheses.
  public static func classify(stderr: String, profile: String) -> OpenFailure {
    let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    let code = text.firstMatch(of: /\((-?\d+)\)\s*$/).flatMap { Int($0.1) }
    switch code {
    case -1743: return .automationDenied
    case DiaScript.profileNotFoundCode: return .profileNotFound(profile)
    case -1712: return .timedOut
    default: return .scriptError(text.isEmpty ? "unknown error" : text)
    }
  }
}
