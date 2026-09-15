# AudioOutputSwitcher

A lightweight macOS menu bar utility that switches system audio output
between your MacBook's built-in speakers and an external device (by default,
tuned for a Dell S2725QC monitor's USB-C speakers), with automatic
switch-on-connect / fall-back-on-disconnect.

- Menu bar icon (`NSStatusItem`), no Dock icon, no app switcher entry.
- Dropdown lists every output device CoreAudio reports; click one to switch.
- Listens for CoreAudio hardware-change notifications (no polling) and:
  - auto-switches to the Dell monitor when it connects
  - falls back to the built-in speakers when it disconnects
- "Auto-Switch to Dell Monitor on Connect" menu toggle to disable this and
  switch manually only.
- Runs at login via a LaunchAgent.

Pure Swift + CoreAudio (`AudioObjectGetPropertyData` /
`AudioObjectSetPropertyData` / `AudioObjectAddPropertyListenerBlock`) — no
dependency on the `SwitchAudioSource` CLI tool, so there's nothing to keep
installed via Homebrew and one less moving part to break.

## Requirements

- macOS 13+
- Swift toolchain (Xcode Command Line Tools are enough — no full Xcode
  needed; this is a Swift Package Manager project, built and verified with
  `swift build` directly)

## Build, sign, and run locally

```bash
cd AudioOutputSwitcher
./scripts/build.sh
```

This:
1. Runs `swift build -c release`.
2. Packages the binary into `~/Applications/AudioOutputSwitcher.app` with a
   minimal `Info.plist` (`LSUIElement = true`, so no Dock icon).
3. Ad-hoc code-signs the bundle (`codesign --sign -`), which is enough to
   run it locally under Gatekeeper without an Apple Developer account. This
   is a self-signature, not an Apple-notarized one — fine for your own
   Mac, not for distributing to others.

Run it once to try it out:

```bash
open ~/Applications/AudioOutputSwitcher.app
```

You should see a speaker icon appear in the menu bar. Click it to see the
device list; your current default output has a checkmark.

To quit: click the icon → **Quit**, or `killall AudioOutputSwitcher`.

## Install as a LaunchAgent (start at login)

```bash
./scripts/install-launch-agent.sh
```

This copies `LaunchAgent/com.danhirst.audiooutputswitcher.plist` to
`~/Library/LaunchAgents/`, pointing it at the app bundle in
`~/Applications`, and loads it immediately with `launchctl bootstrap`. From
now on it starts automatically at login and restarts if it ever exits
unexpectedly (`KeepAlive` / `SuccessfulExit = false`), but won't relaunch in
a crash loop from a manual quit since `RunAtLoad` only fires at login.

Logs go to `/tmp/audiooutputswitcher.log` and `.err` — check there if it
doesn't appear after login.

To remove it:

```bash
./scripts/uninstall-launch-agent.sh
```

### After rebuilding

Re-run `./scripts/build.sh` then `./scripts/install-launch-agent.sh` again
— the install script bootouts the old LaunchAgent and bootstraps it fresh,
so it always launches the newly built binary.

## No volume control on the Dell S2725QC

The Dell's USB-C audio device doesn't expose a volume (or mute) property to
CoreAudio at all — confirmed with `AudioObjectHasProperty` against
`kAudioDevicePropertyVolumeScalar` on both the master element and per-channel
elements, all `false`. This means macOS's volume keys, the menu bar slider,
and any app (this one included) have nothing to adjust: there's no
software-level fix, since the HAL property simply isn't there.

This isn't a bug in AudioOutputSwitcher — it's how the monitor's audio
device reports itself. Control the volume from the monitor's own on-screen
menu/buttons instead (that's what worked in practice). A workaround exists
if you want in-Mac control anyway:
[SoundSource](https://rogueamoeba.com/soundsource/) (paid, Rogue Amoeba) can
add a software volume layer on top of devices that lack hardware volume
control, by inserting itself as an aggregate device.

## Customizing the Dell device match

`StatusBarController.swift` matches an output device as "the Dell monitor"
if its CoreAudio device name (as macOS reports it) contains `"s2725qc"` or
`"dell"`, case-insensitively:

```swift
private static let dellNameMatches = ["s2725qc", "dell"]
```

If your monitor's USB audio device reports a different name, check what
CoreAudio actually calls it — open the menu once with the monitor connected
and read the device list — and adjust this array. Edit, then re-run
`scripts/build.sh` (and `install-launch-agent.sh` if it's already running
as a LaunchAgent).

The built-in speakers are detected by transport type
(`kAudioDeviceTransportTypeBuiltIn`), not by name, so that side doesn't
need any adjustment across MacBook models.

## Project layout

```
Package.swift
Sources/AudioOutputSwitcher/
  main.swift               — app entry point, sets .accessory activation policy
  AppDelegate.swift        — creates the StatusBarController on launch
  AudioDeviceManager.swift — CoreAudio wrapper: enumerate/get/set default, notifications
  StatusBarController.swift— NSStatusItem + menu, connect/disconnect auto-switch logic
Resources/Info.plist        — bundled into the .app (LSUIElement, bundle id, etc.)
LaunchAgent/*.plist         — LaunchAgent template (installed to ~/Library/LaunchAgents)
scripts/
  build.sh                  — swift build + package .app + ad-hoc codesign
  install-launch-agent.sh   — install/reload the LaunchAgent
  uninstall-launch-agent.sh — remove the LaunchAgent
```

## Notes on reliability choices

- **Native CoreAudio, not a CLI tool**: setting the default output device
  in-process avoids spawning a subprocess per switch and avoids a Homebrew
  dependency being missing/uninstalled later.
- **Notification-driven, not polled**: `AudioObjectAddPropertyListenerBlock`
  on `kAudioHardwarePropertyDevices` fires the moment CoreAudio's device
  list changes, and on `kAudioHardwarePropertyDefaultOutputDevice` so the
  menu's checkmark stays correct even if you change the output device from
  Control Center instead of this app.
- **Small delay before switching to a newly-connected device** (0.75s):
  a USB audio device can appear in the device list slightly before CoreAudio
  has it fully ready to accept being set as the default output; this avoids
  a switch attempt that CoreAudio silently ignores.
- **Both `DefaultOutputDevice` and `DefaultSystemOutputDevice` are set**
  together, matching what Control Center does, so alert sounds follow the
  switch too.
- **No entitlements/sandboxing needed**: enumerating and switching audio
  *output* devices doesn't require microphone permission or any TCC
  prompt, so there's nothing extra to grant on first launch.
