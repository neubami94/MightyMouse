# MightyMouse

A tiny free macOS helper that turns a plain 3-button mouse into a gesture mouse.
Hold the **middle button and drag**:

| Gesture | Action |
|---|---|
| Drag left / right | Smooth switch between Spaces (desktops) |
| Drag up | Mission Control |
| Drag down | App Exposé (windows of the current app) |
| Plain middle click | Passes through unchanged |

It synthesizes macOS's private "dock swipe" gesture events for the smooth
horizontal Space animation, and uses the private `CoreDockSendNotification` for the
vertical actions (which macOS 26 "Tahoe" no longer triggers via dock swipes).

> 🎬 [See MightyMouse in action](https://www.youtube.com/watch?v=dQw4w9WgXcQ) before you install.

## Requirements

- macOS 13+ (developed on macOS 26.6, Apple Silicon)
- Xcode command line tools (`swiftc`)

## Install

```bash
./setup-cert.sh   # one-time: creates a stable self-signed signing certificate
./build.sh        # compile + package + sign MightyMouse.app
./install.sh      # install & load the login LaunchAgent
```

Then grant Accessibility once: **System Settings → Privacy & Security → Accessibility →
enable “MightyMouse”**. The helper waits for the permission and picks it up
automatically within ~2 s.

> The self-signed certificate gives the app a stable identity, so the Accessibility
> grant **survives rebuilds** instead of being invalidated on every re-sign.

## Develop / rebuild

```bash
./build.sh restart   # rebuild, re-sign, reload the agent (grant persists)
tail -f mightymouse.log       # runtime log
```

## Tunables

Edit the constants at the top of `main.swift`:

| Constant | Meaning |
|---|---|
| `gestureButton` | Mouse button that triggers gestures (2 = middle) |
| `axisThreshold` | Pixels of movement before the gesture axis locks |
| `horizontalSign` | Flip if left/right feels reversed |
| `verticalFireThreshold` | Pixels of vertical drag before up/down fires |
| `scaleH` | Horizontal sensitivity of the Space animation |

## Files

- `main.swift` — the whole gesture engine
- `build.sh` — compile, package into `MightyMouse.app`, sign
- `setup-cert.sh` — create the self-signed signing certificate
- `install.sh` — install/load the login LaunchAgent
- `Info.plist` — app bundle metadata (stable `CFBundleIdentifier` for TCC)

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.neubami94.mightyMouse.plist
rm ~/Library/LaunchAgents/com.neubami94.mightyMouse.plist
```
