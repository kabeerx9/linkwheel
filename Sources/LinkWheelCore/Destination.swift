import Foundation

/// Where a link can go. Dia profiles are matched by display name at open time,
/// because Dia's scripting interface exposes names, not profile folders.
public enum Destination: Equatable, Sendable {
  case dia(DiaProfile)
  case safari

  public var title: String {
    switch self {
    case .dia(let profile): profile.name
    case .safari: "Safari"
    }
  }
}

/// Dia profiles in Dia's own order, then Safari last.
public func destinations(diaProfiles: [DiaProfile]) -> [Destination] {
  diaProfiles.map(Destination.dia) + [.safari]
}

/// Only web and local HTML links are routed; anything else is refused rather than guessed at.
public func isRoutable(_ url: URL) -> Bool {
  switch url.scheme?.lowercased() {
  case "http", "https": url.host() != nil
  case "file": true
  default: false
  }
}

/// What the hub shows: host plus a shortened path, e.g. "github.com/Shotgun…/pull/467".
public func displayString(for url: URL, maxPathLength: Int = 28) -> (host: String, path: String) {
  guard url.scheme != "file" else { return (url.lastPathComponent, "local file") }
  let host = (url.host() ?? "").replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
  var path = url.path()
  if path == "/" { path = "" }
  if path.count > maxPathLength {
    path = String(path.prefix(maxPathLength / 2)) + "…" + String(path.suffix(maxPathLength / 2))
  }
  return (host, path)
}
