import Cocoa
import CoreGraphics
import IOKit.hid

// Middle-button drag -> smooth Space / Mission Control switching.
// Synthesizes macOS's private "dock swipe" gesture events (pre-macOS 27 CGEventField path).

let dockActions = ["missioncontrol": "com.apple.expose.awake", "appexpose": "com.apple.expose.front.awake",
                   "showdesktop": "com.apple.showdesktop.awake"]

func untilComponents(_ text: String) -> DateComponents? {
    let parts = text.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
    return DateComponents(hour: parts[0], minute: parts[1])
}

struct GlobalConfig: Codable {
    var gestureButton: Int64 = 2
    var gestureButtonByDevice: [String: Int64] = [:]   // e.g. "MX Master 3S": 5
    var reverseMouseScroll = false
    var reverseTrackpadScroll = false
    var axisThreshold: Double = 8.0
    var horizontalSign: Double = -1.0
    var verticalFireThreshold: Double = 30.0
    var scaleH: Double = 1.0 / (Double(NSScreen.main?.frame.width ?? 1440) + 100.0)
    var logInputEvents = false
    var showMenuBarIcon = true
    var gestureClickShortcut: String?   // sent on a gesture button click without drag; default replays the click
    var jiggleUntil: String?   // "HH:mm"; the jiggler switches itself off at the next such time
    var jiggleSeconds: Double = 30   // idle seconds before a nudge; toggled from the menu bar icon
    var buttonShortcuts: [String: String] = [:]   // e.g. "5": "ctrl+shift+cmd+4"
    var buttonShortcutsByDevice: [String: [String: String]] = [:]   // overrides buttonShortcuts per mouse name
    var shortcuts: [Int64: Shortcut] = [:]
    var shortcutsByDevice: [String: [Int64: Shortcut]] = [:]

    enum CodingKeys: String, CodingKey {
        case gestureButton, gestureButtonByDevice, reverseMouseScroll, reverseTrackpadScroll, axisThreshold
        case horizontalSign, verticalFireThreshold, scaleH, logInputEvents, buttonShortcuts, buttonShortcutsByDevice, jiggleSeconds, jiggleUntil, showMenuBarIcon, gestureClickShortcut
    }

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gestureButton = try values.decodeIfPresent(Int64.self, forKey: .gestureButton) ?? gestureButton
        gestureButtonByDevice = try values.decodeIfPresent([String: Int64].self, forKey: .gestureButtonByDevice) ?? gestureButtonByDevice
        reverseMouseScroll = try values.decodeIfPresent(Bool.self, forKey: .reverseMouseScroll) ?? reverseMouseScroll
        reverseTrackpadScroll = try values.decodeIfPresent(Bool.self, forKey: .reverseTrackpadScroll) ?? reverseTrackpadScroll
        axisThreshold = try values.decodeIfPresent(Double.self, forKey: .axisThreshold) ?? axisThreshold
        horizontalSign = try values.decodeIfPresent(Double.self, forKey: .horizontalSign) ?? horizontalSign
        verticalFireThreshold = try values.decodeIfPresent(Double.self, forKey: .verticalFireThreshold) ?? verticalFireThreshold
        scaleH = try values.decodeIfPresent(Double.self, forKey: .scaleH) ?? scaleH
        logInputEvents = try values.decodeIfPresent(Bool.self, forKey: .logInputEvents) ?? logInputEvents
        buttonShortcuts = try values.decodeIfPresent([String: String].self, forKey: .buttonShortcuts) ?? buttonShortcuts
        showMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
        gestureClickShortcut = try values.decodeIfPresent(String.self, forKey: .gestureClickShortcut)
        if let text = gestureClickShortcut, dockActions[text.lowercased()] == nil, Shortcut(text) == nil {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid gestureClickShortcut: \(text)"))
        }
        jiggleUntil = try values.decodeIfPresent(String.self, forKey: .jiggleUntil)
        jiggleSeconds = try values.decodeIfPresent(Double.self, forKey: .jiggleSeconds) ?? jiggleSeconds
        buttonShortcutsByDevice = try values.decodeIfPresent([String: [String: String]].self, forKey: .buttonShortcutsByDevice) ?? buttonShortcutsByDevice
        func parse(_ table: [String: String]) throws -> [Int64: Shortcut] {
            var result: [Int64: Shortcut] = [:]
            for (button, text) in table {
                guard let number = Int64(button), number >= 2, let shortcut = Shortcut(text) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                        debugDescription: "Invalid button shortcut \(button): \(text)"))
                }
                result[number] = shortcut
            }
            return result
        }
        shortcuts = try parse(buttonShortcuts)
        shortcutsByDevice = try buttonShortcutsByDevice.mapValues(parse)
        if let until = jiggleUntil, untilComponents(until) == nil {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid jiggleUntil, expected HH:mm"))
        }
        guard jiggleSeconds.isFinite, jiggleSeconds > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid jiggleSeconds"))
        }
        guard gestureButton >= 2, gestureButtonByDevice.values.allSatisfy({ $0 >= 2 && $0 <= Int64(UInt32.max) }), gestureButton <= Int64(UInt32.max),
              axisThreshold.isFinite, axisThreshold > 0,
              horizontalSign == -1 || horizontalSign == 1,
              verticalFireThreshold.isFinite, verticalFireThreshold > 0,
              scaleH.isFinite, scaleH > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Invalid gesture button, threshold, direction, or sensitivity"))
        }
    }
}

// "ctrl+shift+cmd+4" -> virtual key code + modifier flags (US layout key positions).
struct Shortcut {
    static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "shift": .maskShift, "ctrl": .maskControl, "alt": .maskAlternate, "opt": .maskAlternate,
    ]
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    let code: CGKeyCode
    let flags: CGEventFlags

    init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+").map(String.init)
        guard let last = parts.popLast(), let code = Shortcut.codes[last] else { return nil }
        var flags: CGEventFlags = []
        for part in parts {
            guard let flag = Shortcut.modifiers[part] else { return nil }
            flags.insert(flag)
        }
        self.code = code
        self.flags = flags
    }

    func post() {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            // arrow keys carry the fn flag; without it Mission Control shortcuts like ctrl+up are ignored
            event?.flags = (123...126).contains(code) ? flags.union(.maskSecondaryFn) : flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

let globalConfigURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/MightyMouse/config.plist")
var globalConfig: GlobalConfig = {
    do {
        if FileManager.default.fileExists(atPath: globalConfigURL.path) {
            return try PropertyListDecoder().decode(GlobalConfig.self, from: Data(contentsOf: globalConfigURL))
        }
        let config = GlobalConfig()
        try FileManager.default.createDirectory(
            at: globalConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(config).write(to: globalConfigURL, options: .atomic)
        return config
    } catch {
        NSLog("mightymouse: couldn't load global config %@: %@", globalConfigURL.path, error.localizedDescription)
        exit(EXIT_FAILURE)
    }
}()

// ---- Tunables ----
var gestureButton: Int64 { globalConfig.gestureButton }
var axisThreshold: Double { globalConfig.axisThreshold }
var horizontalSign: Double { globalConfig.horizontalSign }
let syntheticMagic: Int64 = 0x4D47    // "MG" marker on our own re-synthesized clicks

typealias CopyIOHIDEventFn = @convention(c) (CGEvent) -> UnsafeMutableRawPointer?
typealias IOHIDEventGetFloatValueFn = @convention(c) (UnsafeRawPointer, UInt32) -> Double
typealias IOHIDEventSetFloatValueFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Double) -> Void

// Private APIs to reach the HID event embedded in a Quartz scroll event, so its deltas can be reversed too.
let copyIOHIDEvent: CopyIOHIDEventFn? = {
    guard let library = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
          let symbol = dlsym(library, "CGEventCopyIOHIDEvent") else { return nil }
    return unsafeBitCast(symbol, to: CopyIOHIDEventFn.self)
}()
let getHIDEventFloatValue: IOHIDEventGetFloatValueFn? = {
    guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
          let symbol = dlsym(library, "IOHIDEventGetFloatValue") else { return nil }
    return unsafeBitCast(symbol, to: IOHIDEventGetFloatValueFn.self)
}()
let setHIDEventFloatValue: IOHIDEventSetFloatValueFn? = {
    guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
          let symbol = dlsym(library, "IOHIDEventSetFloatValue") else { return nil }
    return unsafeBitCast(symbol, to: IOHIDEventSetFloatValueFn.self)
}()

var configFileContents: [URL: Data] = [:]
var configReloadErrors: [URL: String] = [:]

func reloadConfig() {
    let url = globalConfigURL
    do {
        let data = try Data(contentsOf: url)
        guard configFileContents[url] != data else {
            configReloadErrors.removeValue(forKey: url)
            return
        }
        globalConfig = try PropertyListDecoder().decode(GlobalConfig.self, from: data)
        configFileContents[url] = data
        configReloadErrors.removeValue(forKey: url)
        NSLog("mightymouse: reloaded config %@", url.path)
    } catch {
        let message = error.localizedDescription
        if configReloadErrors[url] != message {
            NSLog("mightymouse: couldn't reload config %@; keeping previous settings: %@", url.path, message)
            configReloadErrors[url] = message
        }
    }
}

// dock swipe types
let kTypeHorizontal = 1
let kTypeVertical = 2
// IOHIDEvent phases
let phaseBegan = 1, phaseChanged = 2, phaseEnded = 4, phaseCancelled = 8
let kDockSwipe = 23

let screenWidth: Double = Double(NSScreen.main?.frame.width ?? 1440)
let screenHeight: Double = Double(NSScreen.main?.frame.height ?? 900)
// approximate scaling: originOffset ~1.0 across one screen width / height
var scaleH: Double { globalConfig.scaleH }

// ---- Gesture state (globals; the tap callback is a C function, no captures) ----
var active = false
var began = false
var activeGestureButton = gestureButton
var axis = 0            // 0 unknown, 1 horizontal, 2 vertical
var sumX = 0.0
var sumY = 0.0
// Bumped on every new gesture so stale delayed end-event re-sends are dropped.
var swipeGeneration = 0

// ---- Dock swipe posting state ----
var originOffset = 0.0
var lastDelta = 0.0

func f32bits(_ x: Double) -> Int64 {
    return Int64(Float(x).bitPattern)
}

func weirdType(_ type: Int) -> Double {
    return Double(Float(bitPattern: UInt32(type)))
}

func postDockSwipe(delta d: Double, type: Int, phase phaseIn: Int) {
    var phase = phaseIn
    if phase == phaseBegan {
        originOffset = d
    } else if phase == phaseChanged {
        if d == 0 { return }
        originOffset += d
    }

    var exitSpeed = 0.0
    if phase == phaseEnded || phase == phaseCancelled {
        exitSpeed = lastDelta * 100.0
    }
    if phase == phaseEnded {
        let s1 = (lastDelta > 0) ? 1.0 : (lastDelta < 0 ? -1.0 : 0.0)
        let s2 = (originOffset > 0) ? 1.0 : (originOffset < 0 ? -1.0 : 0.0)
        if s1 != s2 { phase = phaseCancelled }
    }

    let wt = weirdType(type)

    // type 29 (NSEventTypeGesture)
    let e29 = CGEvent(source: nil)
    e29?.setDoubleValueField(CGEventField(rawValue: 55)!, value: 29)
    e29?.setDoubleValueField(CGEventField(rawValue: 41)!, value: 33231)

    // type 30 carrying the dock swipe payload
    let e30 = CGEvent(source: nil)
    e30?.setDoubleValueField(CGEventField(rawValue: 55)!, value: 30)
    e30?.setDoubleValueField(CGEventField(rawValue: 110)!, value: Double(kDockSwipe))
    e30?.setDoubleValueField(CGEventField(rawValue: 132)!, value: Double(phase))
    e30?.setDoubleValueField(CGEventField(rawValue: 134)!, value: Double(phase))
    e30?.setDoubleValueField(CGEventField(rawValue: 124)!, value: originOffset)
    e30?.setIntegerValueField(CGEventField(rawValue: 135)!, value: f32bits(originOffset))
    e30?.setDoubleValueField(CGEventField(rawValue: 41)!, value: 33231)
    e30?.setDoubleValueField(CGEventField(rawValue: 119)!, value: wt)
    e30?.setDoubleValueField(CGEventField(rawValue: 139)!, value: wt)
    e30?.setDoubleValueField(CGEventField(rawValue: 123)!, value: Double(type))
    e30?.setDoubleValueField(CGEventField(rawValue: 165)!, value: Double(type))
    e30?.setIntegerValueField(CGEventField(rawValue: 136)!, value: 0)
    if phase == phaseEnded || phase == phaseCancelled {
        e30?.setDoubleValueField(CGEventField(rawValue: 129)!, value: exitSpeed)
        e30?.setDoubleValueField(CGEventField(rawValue: 130)!, value: exitSpeed)
    }

    e30?.post(tap: .cgSessionEventTap)
    e29?.post(tap: .cgSessionEventTap)

    // Double/triple re-send of end events to avoid the "stuck" transition bug.
    // Guarded by the gesture generation so a new gesture cancels a previous
    // gesture's pending re-sends (otherwise a quick L->R fires the old direction twice).
    if phase == phaseEnded || phase == phaseCancelled {
        let gen = swipeGeneration
        for delay in [0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if gen != swipeGeneration { return }
                e30?.post(tap: .cgSessionEventTap)
                e29?.post(tap: .cgSessionEventTap)
            }
        }
    }

    lastDelta = d
}

func synthesizeOtherClick(at p: CGPoint, button: CGMouseButton) {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(mouseEventSource: src, mouseType: .otherMouseDown, mouseCursorPosition: p, mouseButton: button)
    let up = CGEvent(mouseEventSource: src, mouseType: .otherMouseUp, mouseCursorPosition: p, mouseButton: button)
    down?.setIntegerValueField(.eventSourceUserData, value: syntheticMagic)
    up?.setIntegerValueField(.eventSourceUserData, value: syntheticMagic)
    down?.post(tap: .cgSessionEventTap)
    up?.post(tap: .cgSessionEventTap)
}

// Vertical dock swipes no longer open Mission Control / App Exposé on macOS 26 (Tahoe).
// Trigger them via the private CoreDockSendNotification, which ignores keyboard-shortcut settings.
typealias CoreDockSendNotificationFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void
let coreDockSend: CoreDockSendNotificationFn? = {
    guard let sym = dlsym(dlopen(nil, RTLD_NOW), "CoreDockSendNotification") else { return nil }
    return unsafeBitCast(sym, to: CoreDockSendNotificationFn.self)
}()

func triggerDock(_ notification: String) {
    coreDockSend?(notification as CFString, nil)
}

let missionControlNote = "com.apple.expose.awake"
let appExposeNote = "com.apple.expose.front.awake"
var verticalFireThreshold: Double { globalConfig.verticalFireThreshold }

var lastScrollLogTime: UInt64 = 0

// Trackpad (and Magic Mouse) scrolls carry a gesture or momentum phase; wheel scrolls, including
// Logi Options+ smooth scrolling, don't.
func isTrackpadScroll(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0 ||
        event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
}

// The tap's CGEvent carries no HID event for button clicks, so remember which mouse pressed a button last.
var lastButtonDevice: String?
let hidManager: IOHIDManager = {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 2] as CFDictionary)
    IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
        let element = IOHIDValueGetElement(value)
        guard IOHIDElementGetUsagePage(element) == kHIDPage_Button, IOHIDValueGetIntegerValue(value) != 0,
              let name = IOHIDDeviceGetProperty(IOHIDElementGetDevice(element), kIOHIDProductKey as CFString) as? String
        else { return }
        lastButtonDevice = name
    }, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    return manager
}()

func deviceName(of event: CGEvent) -> String? { lastButtonDevice }

func gestureButton(for event: CGEvent) -> Int64 {
    guard !globalConfig.gestureButtonByDevice.isEmpty, let name = deviceName(of: event) else { return gestureButton }
    return globalConfig.gestureButtonByDevice[name] ?? gestureButton
}

func shortcut(for event: CGEvent) -> Shortcut? {
    let number = event.getIntegerValueField(.mouseEventButtonNumber)
    if !globalConfig.shortcutsByDevice.isEmpty, let name = deviceName(of: event),
       let table = globalConfig.shortcutsByDevice[name] { return table[number] }
    return globalConfig.shortcuts[number]
}

func logInputEvent(_ event: CGEvent) {
    guard globalConfig.logInputEvents else { return }
    if event.type == .scrollWheel {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastScrollLogTime >= 1_000_000_000 else { return }
        lastScrollLogTime = now
        NSLog("mightymouse: scroll source=%@ phase=%lld momentum=%lld continuous=%lld",
              isTrackpadScroll(event) ? "trackpad" : "mouse",
              event.getIntegerValueField(.scrollWheelEventScrollPhase),
              event.getIntegerValueField(.scrollWheelEventMomentumPhase),
              event.getIntegerValueField(.scrollWheelEventIsContinuous))
    } else {
        NSLog("mightymouse: button=%lld device=%@", event.getIntegerValueField(.mouseEventButtonNumber),
              deviceName(of: event) ?? "unknown")
    }
}

func reverseScroll(_ event: CGEvent) {
    let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let deltaX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let pointY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let pointX = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let fixedY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let fixedX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

    if let copyIOHIDEvent, let getHIDEventFloatValue, let setHIDEventFloatValue,
       let hidEvent = copyIOHIDEvent(event) {
        defer { Unmanaged<CFTypeRef>.fromOpaque(hidEvent).release() }
        let y = getHIDEventFloatValue(UnsafeRawPointer(hidEvent), 0x60001)
        let x = getHIDEventFloatValue(UnsafeRawPointer(hidEvent), 0x60000)
        setHIDEventFloatValue(hidEvent, 0x60001, -y)
        setHIDEventFloatValue(hidEvent, 0x60000, -x)
    }

    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -deltaX)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedY)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixedX)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pointY)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pointX)
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    let pass = Unmanaged.passUnretained(event)

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
        return pass
    }

    if type == .scrollWheel {
        logInputEvent(event)
        if isTrackpadScroll(event) ? globalConfig.reverseTrackpadScroll : globalConfig.reverseMouseScroll {
            reverseScroll(event)
        }
        return pass
    }

    if type == .leftMouseDown || type == .rightMouseDown {
        logInputEvent(event)
        return pass
    }

    // let our own re-synthesized clicks through untouched
    if event.getIntegerValueField(.eventSourceUserData) == syntheticMagic {
        return pass
    }

    switch type {
    case .otherMouseDown:
        logInputEvent(event)
        if let shortcut = shortcut(for: event) {
            shortcut.post()
            return nil
        }
        let button = gestureButton(for: event)
        if event.getIntegerValueField(.mouseEventButtonNumber) != button { return pass }
        active = true
        activeGestureButton = button
        began = false
        axis = 0
        sumX = 0
        sumY = 0
        swipeGeneration &+= 1
        return nil // swallow; re-synthesized later if it turns out to be a plain click

    case .otherMouseDragged:
        if shortcut(for: event) != nil { return nil }
        if !active || event.getIntegerValueField(.mouseEventButtonNumber) != activeGestureButton { return pass }
        let dx = event.getDoubleValueField(.mouseEventDeltaX)
        let dy = event.getDoubleValueField(.mouseEventDeltaY)
        sumX += dx
        sumY += dy
        if axis == 0 {
            if max(abs(sumX), abs(sumY)) >= axisThreshold {
                axis = abs(sumX) >= abs(sumY) ? 1 : 2
                began = true
                if axis == 1 {
                    postDockSwipe(delta: 0.0, type: kTypeHorizontal, phase: phaseBegan)
                }
            }
        }
        if began && axis == 1 {
            postDockSwipe(delta: horizontalSign * dx * scaleH, type: kTypeHorizontal, phase: phaseChanged)
        }
        return nil

    case .otherMouseUp:
        if shortcut(for: event) != nil { return nil }
        if !active || event.getIntegerValueField(.mouseEventButtonNumber) != activeGestureButton { return pass }
        active = false
        if began {
            if axis == 1 {
                postDockSwipe(delta: 0.0, type: kTypeHorizontal, phase: phaseEnded)
            } else if axis == 2 {
                if abs(sumY) >= verticalFireThreshold {
                    triggerDock(sumY < 0 ? missionControlNote : appExposeNote)
                }
            }
            began = false
            return nil
        } else {
            if let text = globalConfig.gestureClickShortcut {
                if let note = dockActions[text.lowercased()] { triggerDock(note) } else { Shortcut(text)?.post() }
                return nil
            }
            // no drag -> replay the configured button click
            let number = UInt32(event.getIntegerValueField(.mouseEventButtonNumber))
            synthesizeOtherClick(at: event.location, button: CGMouseButton(rawValue: number) ?? .center)
            return nil
        }

    default:
        return pass
    }
}

let mask: CGEventMask =
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.rightMouseDown.rawValue) |
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseDragged.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue) |
    (1 << CGEventType.scrollWheel.rawValue)

var eventTap: CFMachPort?

// When launched by launchd the binary itself needs Accessibility permission.
// Prompt for it and wait until it is granted instead of bailing out.
if !AXIsProcessTrusted() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
}

func makeTap() -> CFMachPort? {
    return CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: callback,
        userInfo: nil
    )
}

eventTap = makeTap()
while eventTap == nil {
    NSLog("mightymouse: waiting for Accessibility permission...")
    Thread.sleep(forTimeInterval: 2.0)
    eventTap = makeTap()
}
let tap = eventTap!
_ = hidManager

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
var jiggling = false
var jiggleDeadline: Date?
func setJiggling(_ on: Bool, for hours: Double? = nil) {
    jiggling = on
    jiggleDeadline = !on ? nil : hours.map { Date().addingTimeInterval($0 * 3600) } ??
        globalConfig.jiggleUntil.flatMap(untilComponents).flatMap {
            Calendar.current.nextDate(after: Date(), matching: $0, matchingPolicy: .nextTime)
        }
    jiggleItem.state = on ? .on : .off
    statusItem.button?.appearsDisabled = !on
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
final class JiggleToggle: NSObject {
    @objc func timed(_ item: NSMenuItem) { setJiggling(true, for: Double(item.tag)) }
    @objc func toggle(_ item: NSMenuItem) {
        setJiggling(!jiggling)
    }
}
let jiggleToggle = JiggleToggle()
statusItem.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MightyMouse")
statusItem.button?.appearsDisabled = true
let statusMenu = NSMenu()
let jiggleItem = NSMenuItem(title: "Mouse jiggler", action: #selector(JiggleToggle.toggle(_:)), keyEquivalent: "")
jiggleItem.target = jiggleToggle
statusMenu.addItem(jiggleItem)
for hours in [1, 2, 4, 8] {
    let item = NSMenuItem(title: "Jiggle for \(hours) h", action: #selector(JiggleToggle.timed(_:)), keyEquivalent: "")
    item.target = jiggleToggle
    item.tag = hours
    statusMenu.addItem(item)
}
statusMenu.addItem(.separator())
statusMenu.addItem(withTitle: "Quit MightyMouse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
statusItem.menu = statusMenu

let configReloadTimer = Timer(timeInterval: 1.0, repeats: true) { _ in
    reloadConfig()
    statusItem.isVisible = globalConfig.showMenuBarIcon
    if let deadline = jiggleDeadline, Date() >= deadline { setJiggling(false) }
    // Mouse jiggler: after N idle seconds nudge the pointer 1px and back.
    let n = globalConfig.jiggleSeconds
    if jiggling, CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!) >= n,
       let here = CGEvent(source: nil)?.location {
        for dx in [1.0, 0.0] {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: here.x + dx, y: here.y), mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
}
RunLoop.main.add(configReloadTimer, forMode: .common)
CGEvent.tapEnable(tap: tap, enable: true)
NSLog("mightymouse: running (button=\(gestureButton), screen=\(screenWidth)x\(screenHeight))")
app.run()
