# LinkWheel

A tiny macOS default browser that asks where every link should go. Click a link anywhere and a
radial menu opens at the cursor: pick a Dia profile or Safari with the mouse or keys 1–9, or press
Esc to drop the link.

## Why

Dia keeps each account in its own profile, but links from other apps land in whichever profile was
used last, so you end up signed in to the wrong account. LinkWheel puts the choice at the click.

## How it works

- **Profiles** come from Dia's Chromium `Local State` file, read every time the wheel opens. New and
  renamed profiles appear without configuration, and each wedge uses the profile's Dia colour.
- **Opening** runs a small AppleScript through `osascript` (`Sources/LinkWheelCore/DiaScript.swift`)
  that focuses the profile by name and creates the tab. The URL is passed as an argument, never
  spliced into the script.
- **Failures never open the link elsewhere.** If automation is denied, the profile is gone, or Dia
  does not answer, LinkWheel shows a notification and copies the URL to the clipboard.
- **Speed**: it stays running as a background agent (no Dock icon, starts at login), and the wheel
  is a non-activating panel, so the app you clicked in keeps focus.

Opening LinkWheel from Spotlight or Finder shows a small info window: default-browser status, the
profiles it found, and a start-at-login switch.

## Custom logos

Put an image at `~/Library/Application Support/LinkWheel/Logos/<profile name>.png` to replace the
profile's monogram.

## Build

Requires macOS 15 and Swift 6.2+.

```sh
swift test               # core logic tests
scripts/build-app.sh     # builds LinkWheel.app and installs it to ~/Applications
```

Then make it the default browser from the info window, or in System Settings → Desktop & Dock →
Default web browser. The first open asks for permission to control Dia.
