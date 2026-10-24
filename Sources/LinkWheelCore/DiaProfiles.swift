import Foundation

/// A Dia profile as Dia stores it. `folder` ("Default", "Profile 4") is the stable ID;
/// `name` is what Dia's scripting interface matches on.
public struct DiaProfile: Equatable, Sendable {
  public var folder: String
  public var name: String
  /// Dia's per-profile theme colour as 0xAARRGGBB, from `profile_color_seed`.
  public var colorARGB: UInt32?

  public init(folder: String, name: String, colorARGB: UInt32? = nil) {
    self.folder = folder
    self.name = name
    self.colorARGB = colorARGB
  }

  /// Red, green, blue in 0...1.
  public var rgb: (red: Double, green: Double, blue: Double)? {
    colorARGB.map {
      (Double(($0 >> 16) & 0xFF) / 255, Double(($0 >> 8) & 0xFF) / 255, Double($0 & 0xFF) / 255)
    }
  }

  /// First letter of the name, for a monogram badge.
  public var initial: String { name.first.map { String($0).uppercased() } ?? "?" }
}

/// Reads Dia's profile list from the Chromium `Local State` file Dia keeps on disk.
/// Reading the file is instant and needs no automation permission or running Dia.
public enum DiaProfiles {
  public static let localStateURL = URL.homeDirectory
    .appending(path: "Library/Application Support/Dia/User Data/Local State")

  public static func load(from url: URL = localStateURL) -> [DiaProfile] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return profiles(fromLocalState: data)
  }

  /// Ordered by `profile.profiles_order` when present.
  /// Profiles missing from that order (or all of them, if it is absent) follow, sorted by folder.
  public static func profiles(fromLocalState data: Data) -> [DiaProfile] {
    guard
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let profile = root["profile"] as? [String: Any],
      let cache = profile["info_cache"] as? [String: Any]
    else { return [] }

    let order = profile["profiles_order"] as? [String] ?? []
    let unordered = cache.keys.filter { !order.contains($0) }.sorted()
    return (order + unordered).compactMap { folder in
      guard let entry = cache[folder] as? [String: Any],
            let name = entry["name"] as? String, !name.isEmpty
      else { return nil }
      // Chromium stores colours as signed 32-bit ints; reinterpret the bits.
      let color = (entry["profile_color_seed"] as? NSNumber).map { UInt32(bitPattern: $0.int32Value) }
      return DiaProfile(folder: folder, name: name, colorARGB: color)
    }
  }
}
