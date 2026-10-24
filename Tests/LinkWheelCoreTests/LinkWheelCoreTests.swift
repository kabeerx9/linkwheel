import Foundation
import Testing
@testable import LinkWheelCore

@Suite struct DiaProfilesTests {
  private func localState(_ json: String) -> Data { Data(json.utf8) }

  @Test func `follows profiles_order, not dictionary order`() {
    let data = localState("""
      {"profile": {
        "profiles_order": ["Default", "Profile 4", "Profile 5"],
        "info_cache": {
          "Profile 5": {"name": "Goreeva"},
          "Default": {"name": "Personal"},
          "Profile 4": {"name": "Shotgun"}
        }}}
      """)
    #expect(DiaProfiles.profiles(fromLocalState: data).map(\.name) == ["Personal", "Shotgun", "Goreeva"])
  }

  @Test func `profiles missing from the order are appended by folder`() {
    let data = localState("""
      {"profile": {
        "profiles_order": ["Profile 4"],
        "info_cache": {
          "Profile 9": {"name": "New"},
          "Default": {"name": "Personal"},
          "Profile 4": {"name": "Shotgun"}
        }}}
      """)
    #expect(DiaProfiles.profiles(fromLocalState: data).map(\.name) == ["Shotgun", "Personal", "New"])
  }

  @Test func `skips entries without a name and ignores stale order entries`() {
    let data = localState("""
      {"profile": {
        "profiles_order": ["Gone", "Default"],
        "info_cache": {"Default": {"name": "Personal"}, "Profile 2": {"name": ""}}}}
      """)
    #expect(DiaProfiles.profiles(fromLocalState: data).map(\.name) == ["Personal"])
  }

  @Test(arguments: ["", "not json", "{}", #"{"profile": {}}"#, #"{"profile": {"info_cache": 3}}"#])
  func `malformed Local State yields no profiles`(json: String) {
    #expect(DiaProfiles.profiles(fromLocalState: localState(json)).isEmpty)
  }

  @Test func `reads Dia's signed colour seed as ARGB and the folder as the ID`() throws {
    let data = localState(#"{"profile": {"info_cache": {"Profile 4": {"name": "shotgun", "profile_color_seed": -12941116}}}}"#)
    let profile = try #require(DiaProfiles.profiles(fromLocalState: data).first)
    #expect(profile.folder == "Profile 4")
    #expect(profile.colorARGB == 0xFF3A_88C4)
    #expect(profile.initial == "S")
    let rgb = try #require(profile.rgb)
    #expect(abs(rgb.blue - 196.0 / 255) < 1e-9)
  }

  @Test func `profile without a colour seed has no colour`() throws {
    let data = localState(#"{"profile": {"info_cache": {"Default": {"name": "Personal"}}}}"#)
    #expect(try #require(DiaProfiles.profiles(fromLocalState: data).first).colorARGB == nil)
  }

  @Test func `missing file yields no profiles`() {
    #expect(DiaProfiles.load(from: URL(filePath: "/nonexistent/Local State")).isEmpty)
  }
}

@Suite struct DestinationTests {
  @Test func `Dia profiles first, Safari last`() {
    let personal = DiaProfile(folder: "Default", name: "Personal")
    let shotgun = DiaProfile(folder: "Profile 4", name: "Shotgun")
    #expect(destinations(diaProfiles: [personal, shotgun]) == [.dia(personal), .dia(shotgun), .safari])
  }

  @Test func `Safari is always offered, even with no Dia profiles`() {
    #expect(destinations(diaProfiles: []) == [.safari])
  }

  @Test(arguments: [
    ("https://github.com/x", true),
    ("http://localhost:8081", true),
    ("file:///Users/k/page.html", true),
    ("mailto:a@b.com", false),
    ("javascript:alert(1)", false),
    ("https://", false),
  ])
  func `routes only web and file links`(string: String, expected: Bool) throws {
    let url = try #require(URL(string: string))
    #expect(isRoutable(url) == expected)
  }
}

@Suite struct DisplayStringTests {
  @Test func `drops www and a bare slash`() throws {
    let url = try #require(URL(string: "https://www.example.com/"))
    #expect(displayString(for: url) == ("example.com", ""))
  }

  @Test func `shortens long paths in the middle`() throws {
    let url = try #require(URL(string: "https://github.com/Shotgun-Fantasy-Sports-Dev/sfs-native/pull/467"))
    let shown = displayString(for: url, maxPathLength: 20)
    #expect(shown.host == "github.com")
    #expect(shown.path == "/Shotgun-F…e/pull/467")
  }
}

@Suite struct WheelGeometryTests {
  let wheel = WheelGeometry(count: 4, innerRadius: 40, outerRadius: 140)

  @Test(arguments: [
    (0.0, -100.0, 0),  // straight up
    (100.0, 0.0, 1),  // right
    (0.0, 100.0, 2),  // down
    (-100.0, 0.0, 3),  // left
    (-30.0, -100.0, 0),  // slightly left of up still wedge 0 (wraps past 12 o'clock)
  ])
  func `points map to the wedge in that direction`(x: Double, y: Double, expected: Int) {
    #expect(wheel.wedge(atX: x, y: y) == expected)
  }

  @Test func `hub and outside the ring select nothing`() {
    #expect(wheel.wedge(atX: 0, y: 0) == nil)
    #expect(wheel.wedge(atX: 10, y: -20) == nil)
    #expect(wheel.wedge(atX: 0, y: -200) == nil)
  }

  @Test func `label for wedge 1 of 4 sits to the right`() {
    let offset = wheel.labelOffset(of: 1, radius: 90)
    #expect(abs(offset.x - 90) < 1e-9)
    #expect(abs(offset.y) < 1e-9)
  }

  @Test func `every wedge's own label point hits that wedge`() {
    for count in 1...9 {
      let ring = WheelGeometry(count: count, innerRadius: 40, outerRadius: 140)
      for index in 0..<count {
        let p = ring.labelOffset(of: index, radius: 90)
        #expect(ring.wedge(atX: p.x, y: p.y) == index, "count \(count) index \(index)")
      }
    }
  }

  @Test func `number keys select within range only`() {
    #expect(wedgeIndex(forKey: "1", count: 4) == 0)
    #expect(wedgeIndex(forKey: "4", count: 4) == 3)
    #expect(wedgeIndex(forKey: "5", count: 4) == nil)
    #expect(wedgeIndex(forKey: "0", count: 4) == nil)
    #expect(wedgeIndex(forKey: "a", count: 4) == nil)
  }
}

@Suite struct OpenFailureTests {
  @Test(arguments: [
    ("execution error: Not authorized to send Apple events to Dia. (-1743)", OpenFailure.automationDenied),
    ("execution error: Profile not found (9001)", .profileNotFound("Shotgun")),
    ("execution error: Dia got an error: AppleEvent timed out. (-1712)", .timedOut),
  ])
  func `classifies osascript errors by code`(stderr: String, expected: OpenFailure) {
    #expect(OpenFailure.classify(stderr: stderr, profile: "Shotgun") == expected)
  }

  @Test func `unknown errors keep the original text`() {
    let failure = OpenFailure.classify(stderr: "execution error: boom (-2700)\n", profile: "X")
    #expect(failure == .scriptError("execution error: boom (-2700)"))
  }

  @Test func `script never interpolates the URL or profile`() {
    #expect(DiaScript.source.contains("item 1 of argv"))
    #expect(!DiaScript.source.contains("\\("))
  }
}
