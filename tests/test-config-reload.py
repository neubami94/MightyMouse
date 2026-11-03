"""Run the app's config reload logic without installing an event tap."""

from pathlib import Path
import subprocess


source = (Path(__file__).resolve().parents[1] / "main.swift").read_text()
model = source[source.index("struct GlobalConfig:"):source.index("let globalConfigURL")]  # includes Shortcut
reload_logic = source[source.index("var configFileContents:"):source.index("// dock swipe types")]

subprocess.run(
    ["swift", "-"],
    input="import Cocoa\n" + model + """
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try! FileManager.default.removeItem(at: directory) }
let globalConfigURL = directory.appendingPathComponent("config.plist")
var globalConfig = GlobalConfig()
""" + reload_logic + """
let encoder = PropertyListEncoder()
try encoder.encode(globalConfig).write(to: globalConfigURL, options: .atomic)
reloadConfig()

var updated = globalConfig
updated.gestureButton = 6
updated.reverseMouseScroll = true
updated.axisThreshold = 12
updated.horizontalSign = 1
updated.verticalFireThreshold = 40
updated.scaleH = 0.002
updated.buttonShortcuts = ["5": "Ctrl+Shift+Cmd+4"]
try encoder.encode(updated).write(to: globalConfigURL, options: .atomic)
reloadConfig()
assert(globalConfig.gestureButton == 6 && globalConfig.reverseMouseScroll && !globalConfig.reverseTrackpadScroll)
assert(globalConfig.axisThreshold == 12 && globalConfig.horizontalSign == 1)
assert(globalConfig.verticalFireThreshold == 40 && globalConfig.scaleH == 0.002)
let shot = globalConfig.shortcuts[5]!
assert(shot.code == 21 && shot.flags == [.maskControl, .maskShift, .maskCommand])

var badShortcut = updated
badShortcut.buttonShortcuts = ["5": "hyper+4"]
try encoder.encode(badShortcut).write(to: globalConfigURL, options: .atomic)
reloadConfig()
assert(globalConfig.shortcuts[5] != nil)

var invalid = updated
invalid.axisThreshold = 0
try encoder.encode(invalid).write(to: globalConfigURL, options: .atomic)
reloadConfig()
assert(globalConfig.axisThreshold == 12)

try Data("invalid plist".utf8).write(to: globalConfigURL, options: .atomic)
reloadConfig()
assert(globalConfig.reverseMouseScroll && configReloadErrors.count == 1)

// Older files without the newer keys still load with defaults.
try Data(\"\"\"
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>gestureButton</key><integer>3</integer></dict></plist>
\"\"\".utf8).write(to: globalConfigURL, options: .atomic)
reloadConfig()
assert(globalConfig.gestureButton == 3 && !globalConfig.reverseMouseScroll && globalConfig.axisThreshold == 8)
assert(configReloadErrors.isEmpty)
print("Live config reload checks passed")
""",
    text=True,
    check=True,
)
