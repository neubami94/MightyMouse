import Cocoa
import CoreGraphics

// Middle-button drag -> smooth Space / Mission Control switching.
// Synthesizes macOS's private "dock swipe" gesture events (pre-macOS 27 CGEventField path).

// ---- Tunables ----
let gestureButton: Int64 = 2          // 0=left, 1=right, 2=middle
let axisThreshold: Double = 8.0       // px of movement before a gesture axis is locked
let horizontalSign: Double = -1.0     // flip if left/right feels reversed
let syntheticMagic: Int64 = 0x4D47    // "MG" marker on our own re-synthesized clicks

// dock swipe types
let kTypeHorizontal = 1
let kTypeVertical = 2
// IOHIDEvent phases
let phaseBegan = 1, phaseChanged = 2, phaseEnded = 4, phaseCancelled = 8
let kDockSwipe = 23

let screenWidth: Double = Double(NSScreen.main?.frame.width ?? 1440)
let screenHeight: Double = Double(NSScreen.main?.frame.height ?? 900)
// approximate scaling: originOffset ~1.0 across one screen width / height
let scaleH = 1.0 / (screenWidth + 100.0)

// ---- Gesture state (globals; the tap callback is a C function, no captures) ----
var active = false
var began = false
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

func synthesizeMiddleClick(at p: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(mouseEventSource: src, mouseType: .otherMouseDown, mouseCursorPosition: p, mouseButton: .center)
    let up = CGEvent(mouseEventSource: src, mouseType: .otherMouseUp, mouseCursorPosition: p, mouseButton: .center)
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
let verticalFireThreshold = 30.0

let callback: CGEventTapCallBack = { _, type, event, _ in
    let pass = Unmanaged.passUnretained(event)

    // let our own re-synthesized clicks through untouched
    if event.getIntegerValueField(.eventSourceUserData) == syntheticMagic {
        return pass
    }
    if event.getIntegerValueField(.mouseEventButtonNumber) != gestureButton {
        return pass
    }

    switch type {
    case .otherMouseDown:
        active = true
        began = false
        axis = 0
        sumX = 0
        sumY = 0
        swipeGeneration &+= 1
        return nil // swallow; re-synthesized later if it turns out to be a plain click

    case .otherMouseDragged:
        if !active { return pass }
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
        if !active { return pass }
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
            // no drag -> it was a real middle click; replay it
            synthesizeMiddleClick(at: event.location)
            return nil
        }

    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let t = eventTap { CGEvent.tapEnable(tap: t, enable: true) }
        return pass

    default:
        return pass
    }
}

let mask: CGEventMask =
    (1 << CGEventType.otherMouseDown.rawValue) |
    (1 << CGEventType.otherMouseDragged.rawValue) |
    (1 << CGEventType.otherMouseUp.rawValue)

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

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
NSLog("mightymouse: running (button=\(gestureButton), screen=\(screenWidth)x\(screenHeight))")
CFRunLoopRun()
