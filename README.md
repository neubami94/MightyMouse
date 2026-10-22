# MightyMouse

A tiny free macOS helper that turns a plain 3-button mouse into a gesture mouse.
Hold the **middle button and drag**:

| Gesture | Action |
|---|---|
| Drag left / right | Smooth switch between Spaces (desktops) |
| Drag up | Mission Control |
| Drag down | App Exposé (windows of the current app) |
| Plain click | Replayed as a normal click |

It also works as a free alternative to Logi Options+ for MX Master mice (MX Master 3S, MX Master 4, and others): the gesture button gives smoother
Space switching than Options+ (the desktop follows your drag instead of jumping), and several MX Master models can be used on one Mac
(see the per-device settings below).

It synthesizes macOS's private "dock swipe" gesture events for the smooth
horizontal Space animation, and uses the private `CoreDockSendNotification` for the
vertical actions (which macOS 26 "Tahoe" no longer triggers via dock swipes).

It can also reverse mouse and trackpad scrolling independently and send a
keyboard shortcut when an extra mouse button is clicked (see [Tunables](#tunables)).

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

MightyMouse automatically creates
`~/Library/Application Support/MightyMouse/config.plist` from the defaults below.
Changes apply within about one second of **saving** the file (unsaved editor
changes have no effect); no rebuild or restart is needed. `mightymouse.log`
reports `reloaded config` on success. An invalid or temporarily missing file
keeps the previous settings and reports `couldn't reload config`. A setting
missing from the file uses its default.

| Setting | Meaning | Available values | Default |
|---|---|---|---|
| `gestureButton` | Mouse button that triggers gestures | `2` = middle; `3`, `4`, or another OS-reported extra button | `2` |
| `gestureButtonByDevice` | Per-mouse override of `gestureButton`, keyed by the mouse's product name (shown as `device=` when `logInputEvents` is on) | Dictionary of name to button number, e.g. `MX Master 3S` → `5`, `MX Master 4` → `6` | empty |
| `buttonShortcutsByDevice` | Per-mouse `buttonShortcuts`, keyed by product name; a listed mouse uses only its own table | Dictionary of name to `buttonShortcuts`-style dictionary | empty |
| `showMenuBarIcon` | Show the menu bar icon (mouse jiggler toggle, Quit) | `true` or `false` | `true` |
| `jiggleUntil` | Used by the plain "Mouse jiggler" menu item (the "Jiggle for N h" items use their own duration). Time of day (`HH:mm`, 24 h) when the jiggler switches itself off, so the Mac can sleep afterwards; the next such time after you enable it | e.g. `16:00` | unset (jiggles until switched off) |
| `jiggleSeconds` | Mouse jiggler interval: while "Mouse jiggler" is checked in the menu bar icon (off at launch; needs `showMenuBarIcon`), nudge the pointer 1 px and back after this many idle seconds, keeping the Mac awake | Positive number | `30` |
| `reverseMouseScroll` | Reverse scroll wheel direction | `true` or `false` | `false` |
| `reverseTrackpadScroll` | Reverse trackpad (and Magic Mouse) scroll direction | `true` or `false` | `false` |
| `axisThreshold` | Movement before the gesture axis locks, in pixels | Positive number | `8.0` |
| `horizontalSign` | Horizontal gesture direction | `-1.0` or `1.0` | `-1.0` |
| `verticalFireThreshold` | Vertical drag before up/down fires, in pixels | Positive number | `30.0` |
| `scaleH` | Horizontal sensitivity of the Space animation | Positive number | `1.0 / (screenWidth + 100.0)` |
| `logInputEvents` | Log mouse button numbers and scroll sources for diagnosis | `true` or `false` | `false` |
| `gestureClickShortcut` | Action when the gesture button is clicked without dragging: a Dock action or a shortcut in the `buttonShortcuts` format | `missionControl`, `appExpose`, or e.g. `ctrl+up` | unset (the click is replayed) |
| `buttonShortcuts` | Keyboard shortcut sent when an extra button is clicked | Dictionary of button number (string, `2`+) to shortcut, e.g. `5` → `ctrl+shift+cmd+4` | empty |

Shortcuts are `+`-separated modifiers (`cmd`, `shift`, `ctrl`, `alt`/`opt`)
followed by one key: a letter, digit, punctuation key, `return`, `tab`,
`space`, `delete`, `escape`, or an arrow (`left`, `right`, `up`, `down`).
Keys use US-layout positions. A mapped button no longer clicks or triggers
gestures. For example, region screenshot to clipboard on the thumb button:

```xml
<key>buttonShortcuts</key>
<dict><key>5</key><string>ctrl+shift+cmd+4</string></dict>
```

The middle button is the default gesture button and the main use case. With
Logi Options+ not remapping them, MX Master 4 buttons report as: left `0`,
right `1`, wheel click `2`, back `3`, forward `4`, thumb button `5`, gesture
button `6`. MX Master 3S has no separate thumb button number: its gesture
button reports as `5`. While Logi Options+ runs it consumes the gesture button (even
when set to "Do nothing") and any button with an Options+ action, so they never
reach MightyMouse. To use the gesture button, quit Options+ and set
`gestureButton` to `6`; use `buttonShortcuts` to replace Options+ button actions.
Left/right (`0`/`1`) aren't supported as gesture triggers.

Using both mice on one computer: set the per-device options, keyed by the product
names MightyMouse logs as `device=` (with `logInputEvents` on):

```xml
<key>gestureButtonByDevice</key>
<dict>
  <key>MX Master 4</key><integer>6</integer>
  <key>MX Master 3S</key><integer>5</integer>
</dict>
<key>buttonShortcutsByDevice</key>
<dict>
  <key>MX Master 4</key>
  <dict><key>5</key><string>ctrl+shift+cmd+4</string></dict>
  <key>MX Master 3S</key>
  <dict/>
</dict>
```

The mouse is identified by whichever device pressed a button last.

To stop Options+ (until the next login), quit its app and run:

```bash
launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.logi.optionsplus.plist
# start it again:
launchctl bootstrap gui/$(id -u) /Library/LaunchAgents/com.logi.optionsplus.plist
```

Without Options+, the mouse uses macOS's own pointer and scroll settings.
Don't run another scroll reverser alongside
`reverseMouseScroll`; two reversals cancel out.

Scrolls with a gesture or momentum phase (trackpad, Magic Mouse) count as
trackpad scrolls; everything else, including Logi Options+ smooth scrolling,
counts as mouse scrolls.

With `logInputEvents` enabled, `mightymouse.log` records button numbers and
how each scroll was classified (at most one scroll message per second). It
doesn't record keyboard input. Disable it after testing.

## Files

- `main.swift` — the whole gesture engine
- `build.sh` — compile, package into `MightyMouse.app`, sign
- `setup-cert.sh` — create the self-signed signing certificate
- `install.sh` — install/load the login LaunchAgent
- `Info.plist` — app bundle metadata (stable `CFBundleIdentifier` for TCC)
- `tests/test-config-reload.py` — config parsing and live reload check (`python3 tests/test-config-reload.py`)

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.neubami94.mightyMouse.plist
rm ~/Library/LaunchAgents/com.neubami94.mightyMouse.plist
```
