import AppKit
import CoreAudio
import Foundation

final class InputController {
    var onVolumeChanged: ((Double) -> Void)?

    private let volumeObserverQueue = DispatchQueue(label: "iControl.VolumeObserver")
    private let keyboardEventSource = CGEventSource(stateID: .hidSystemState)
    private let kbEventSource = CGEventSource(stateID: .hidSystemState)
    private let keyboardTapLocation: CGEventTapLocation = .cghidEventTap
    private let controlArrowTapLocation: CGEventTapLocation = .cgAnnotatedSessionEventTap
    private var lastKnownPosition: CGPoint
    private var lastMoveTime: Date = .distantPast

    private var lastClickTime: Date = .distantPast
    private var lastClickPosition: CGPoint = .zero
    private var lastClickButton: String = ""
    private var consecutiveClickCount: Int = 0

    private var currentPosition: CGPoint {
        CGEvent(source: nil)?.location ?? lastKnownPosition
    }

    init() {
        lastKnownPosition = CGEvent(source: nil)?.location ?? .zero
        startObservingVolumeChanges()
    }

    func moveMouse(dx: Double, dy: Double) {
        let now = Date()
        if now.timeIntervalSince(lastMoveTime) > 1 {
            lastKnownPosition = CGEvent(source: nil)?.location ?? lastKnownPosition
        }

        let nextPoint = CGPoint(
            x: lastKnownPosition.x + dx,
            y: lastKnownPosition.y + dy
        )

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: nextPoint,
            mouseButton: .left
        )
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event?.post(tap: .cghidEventTap)

        lastKnownPosition = nextPoint
        lastMoveTime = now
    }

    func scroll(dx: Double, dy: Double) {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    func mouseClick(button: String) {
        let now = Date()
        let point = currentPosition
        let interval = now.timeIntervalSince(lastClickTime)
        let dx = point.x - lastClickPosition.x
        let dy = point.y - lastClickPosition.y
        let withinPosition = (dx * dx + dy * dy) <= 16   // 4 px radius

        if button == lastClickButton,
           interval <= NSEvent.doubleClickInterval,
           withinPosition,
           consecutiveClickCount < 3 {
            consecutiveClickCount += 1
        } else {
            consecutiveClickCount = 1
        }

        lastClickTime = now
        lastClickPosition = point
        lastClickButton = button

        postClick(button: button, clickState: Int64(consecutiveClickCount))
    }

    func mouseDown(button: String) {
        let (mouseButton, downType, _) = mouseButtonEventTypes(for: button)
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: downType, mouseCursorPosition: currentPosition, mouseButton: mouseButton)
        event?.post(tap: .cghidEventTap)
    }

    func mouseUp(button: String) {
        let (mouseButton, _, upType) = mouseButtonEventTypes(for: button)
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: upType, mouseCursorPosition: currentPosition, mouseButton: mouseButton)
        event?.post(tap: .cghidEventTap)
    }

    func dragMouse(dx: Double, dy: Double) {
        let now = Date()
        if now.timeIntervalSince(lastMoveTime) > 1 {
            lastKnownPosition = CGEvent(source: nil)?.location ?? lastKnownPosition
        }
        let nextPoint = CGPoint(x: lastKnownPosition.x + dx, y: lastKnownPosition.y + dy)
        let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: nextPoint, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event?.post(tap: .cghidEventTap)
        lastKnownPosition = nextPoint
        lastMoveTime = now
    }

    func pressKey(key: String) {
        if let keyPress = keyPress(for: key) {
            postKeyPress(keyPress)
        } else {
            typeText(string: key)
        }
    }

    func typeText(string: String) {
        guard !string.isEmpty else { return }

        let lines = string.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if !line.isEmpty {
                let utf16 = Array(line.utf16)
                let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
                let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
                down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
            }

            if index < lines.count - 1 {
                postKeyPress(KeyPress(keyCode: 36, modifiers: .maskShift))
            }
        }
    }

    func performSystemAction(_ action: String, value: Double? = nil) {
        switch action {
        case "playPause":
            postSystemKey(16)
        case "nextTrack":
            postSystemKey(17)
        case "previousTrack":
            postSystemKey(18)
        case "volumeUp":
            postSystemKey(0)
        case "volumeDown":
            postSystemKey(1)
        case "mute":
            postSystemKey(7)
        case "missionControl":
            postKey(keyCode: 160)
        case "appWindows":
            postKey(keyCode: 99, flags: .maskControl)
        case "launchpad":
            postKey(keyCode: 131)
        case "minimize":
            postKey(keyCode: 46, flags: .maskCommand)
        case "fullscreen":
            postKey(keyCode: 3, flags: [.maskCommand, .maskControl])
        case "delete":
            postKey(keyCode: 51, flags: .maskCommand)
        case "setVolume":
            if let value {
                setVolume(to: value)
            }
		case "brightnessDown":
			postKey(keyCode: 107)
		case "brightnessUp":
			postKey(keyCode: 113)
		case "screenshot":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Screenshot"]
            try? process.run()
		case "siri":
			launchApp("com.apple.Siri")
        default:
            break
        }
    }

    func currentVolumePercentage() -> Double? {
        guard let volume = systemVolume() else { return nil }
        return Double(volume * 100)
    }

    func launchApp(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.contains("."),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", trimmed]
        try? process.run()
    }

    func openURL(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed)
        else { return }

        NSWorkspace.shared.open(url)
    }

	func handleKbInput(_ key: String, flags: KbFlags?) {
		let cgFlags = cgEventFlags(from: flags)

		// ── F keys ──────────────────────────────────────────────────────────────
		if let fKeyCode = fKeyCode(for: key) {
			postKbKey(fKeyCode, flags: cgFlags)
			return
		}

		// ── Named special keys ───────────────────────────────────────────────────
		if let specialCode = kbSpecialKeyCode(for: key) {
			postKbKey(specialCode, flags: cgFlags)
			return
		}

		// ── Printable characters ─────────────────────────────────────────────────
		// Single character — post via CGKeyCode if we have one, else typeText
		if key.count == 1 {
			if let code = alphaNumericKeyCode(for: key.lowercased()) {
				postKbKey(code, flags: cgFlags)
			} else {
				// Symbol with no direct keycode — inject as unicode
				// Flags intentionally not stamped — character already resolved client-side
				let utf16 = Array(key.utf16)
				let down = CGEvent(keyboardEventSource: kbEventSource, virtualKey: 0, keyDown: true)
				let up   = CGEvent(keyboardEventSource: kbEventSource, virtualKey: 0, keyDown: false)
				down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
				up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
				down?.post(tap: keyboardTapLocation)
				up?.post(tap: keyboardTapLocation)
			}
			return
		}
	}

	// ── CGEventFlags from KbFlags ─────────────────────────────────────────────────

	private func cgEventFlags(from flags: KbFlags?) -> CGEventFlags {
		guard let flags else { return [] }
		var result: CGEventFlags = []
		if flags.shift == true { result.insert(.maskShift) }
		if flags.ctrl  == true { result.insert(.maskControl) }
		if flags.opt   == true { result.insert(.maskAlternate) }
		if flags.cmd   == true { result.insert(.maskCommand) }
		return result
	}

	// ── Post a kb key with flags ──────────────────────────────────────────────────

    private func postKbKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let tapLocation: CGEventTapLocation = (flags == .maskControl && isArrowKey(keyCode))
            ? controlArrowTapLocation
            : keyboardTapLocation

        // post modifier keydowns if flags present
        if !flags.isEmpty {
            let modifierCodes = modifierKeyCodes(for: flags)
            var accumulated: CGEventFlags = []
            for code in modifierCodes {
                accumulated.insert(self.flags(forPressedModifierKeyCode: code))
                let modDown = CGEvent(keyboardEventSource: kbEventSource, virtualKey: code, keyDown: true)
                modDown?.flags = accumulated
                modDown?.post(tap: tapLocation)
                usleep(1500)
            }
        }

        let down = CGEvent(keyboardEventSource: kbEventSource, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: kbEventSource, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags   = flags
        down?.post(tap: tapLocation)
        usleep(1500)
        up?.post(tap: tapLocation)
        usleep(1500)

        // post modifier keyups in reverse
        if !flags.isEmpty {
            let modifierCodes = modifierKeyCodes(for: flags)
            var accumulated = flags
            for code in modifierCodes.reversed() {
                accumulated.remove(self.flags(forPressedModifierKeyCode: code))
                let modUp = CGEvent(keyboardEventSource: kbEventSource, virtualKey: code, keyDown: false)
                modUp?.flags = accumulated
                modUp?.post(tap: tapLocation)
                usleep(1500)
            }
        }
    }

	// ── F key codes ───────────────────────────────────────────────────────────────

	private func fKeyCode(for key: String) -> CGKeyCode? {
		switch key {
		case "f1":  return 122
		case "f2":  return 120
		case "f3":  return 99
		case "f4":  return 118
		case "f5":  return 96
		case "f6":  return 97
		case "f7":  return 98
		case "f8":  return 100
		case "f9":  return 101
		case "f10": return 109
		case "f11": return 103
		case "f12": return 111
		default:    return nil
		}
	}

	// ── Special key codes (kb pipeline only) ─────────────────────────────────────

	private func kbSpecialKeyCode(for key: String) -> CGKeyCode? {
		switch key {
		case "escape":              return 53
		case "delete":              return 51
		case "return", "enter":     return 36
		case "tab":                 return 48
		case "space":               return 49
		case "up":                  return 126
		case "down":                return 125
		case "left":                return 123
		case "right":               return 124
		default:                    return nil
		}
	}

    private func mouseButtonEventTypes(for button: String) -> (CGMouseButton, CGEventType, CGEventType) {
        switch button {
        case "right":  return (.right, .rightMouseDown, .rightMouseUp)
        case "middle": return (.center, .otherMouseDown, .otherMouseUp)
        default:       return (.left, .leftMouseDown, .leftMouseUp)
        }
    }

    private func postClick(button: String, clickState: Int64) {
        postClick(button: button, clickState: clickState, source: CGEventSource(stateID: .hidSystemState), point: currentPosition)
    }

    private func postClick(button: String, clickState: Int64, source: CGEventSource?, point: CGPoint) {
        let mouseButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType

        switch button {
        case "right":
            mouseButton = .right
            downType = .rightMouseDown
            upType = .rightMouseUp
        case "middle":
            mouseButton = .center
            downType = .otherMouseDown
            upType = .otherMouseUp
        default:
            mouseButton = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        }

        let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: mouseButton)
        let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: mouseButton)
        down?.setIntegerValueField(.mouseEventClickState, value: clickState)
        up?.setIntegerValueField(.mouseEventClickState, value: clickState)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags = [], tap: CGEventTapLocation? = nil) {
        let postTap = tap ?? keyboardTapLocation
        let down = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: keyCode, keyDown: false)
        if !flags.isEmpty {
            down?.flags = flags
            up?.flags = flags
        }
        down?.post(tap: postTap)
        up?.post(tap: postTap)
    }

    private func postSystemKey(_ key: Int32) {
        postSystemKeyEvent(key, state: 0xA)
        postSystemKeyEvent(key, state: 0xB)
    }

    private func postSystemKeyEvent(_ key: Int32, state: Int32) {
        let data1 = Int((key << 16) | (state << 8))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xA00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func setVolume(to value: Double) {
        let scalar = Float(max(0, min(100, value)) / 100)
        setSystemVolume(scalar)
    }

    private func toggleMute() {
        guard let deviceID = defaultOutputDeviceID() else {
            print("iControl: failed to find default output device for mute")
            return
        }
        let isMuted = isSystemMuted(deviceID: deviceID) ?? false
        setSystemMuted(!isMuted, deviceID: deviceID)
    }

    private func postKeyPress(_ keyPress: KeyPress) {
        let modifierKeyCodes = modifierKeyCodes(for: keyPress.modifiers)
        let tapLocation = tapLocation(for: keyPress)
        var pressedFlags: CGEventFlags = []

        for modifierKeyCode in modifierKeyCodes {
            let modifierFlag = flags(forPressedModifierKeyCode: modifierKeyCode)
            pressedFlags.insert(modifierFlag)
            let modifierDown = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: modifierKeyCode, keyDown: true)
            modifierDown?.flags = pressedFlags
            modifierDown?.post(tap: tapLocation)
            usleep(1500)
        }

        let down = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: keyPress.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: keyPress.keyCode, keyDown: false)
        down?.flags = keyPress.modifiers
        up?.flags = keyPress.modifiers
        down?.post(tap: tapLocation)
        usleep(1500)
        up?.post(tap: tapLocation)
        usleep(1500)

        for modifierKeyCode in modifierKeyCodes.reversed() {
            let modifierFlag = flags(forPressedModifierKeyCode: modifierKeyCode)
            pressedFlags.remove(modifierFlag)
            let modifierUp = CGEvent(keyboardEventSource: keyboardEventSource, virtualKey: modifierKeyCode, keyDown: false)
            modifierUp?.flags = pressedFlags
            modifierUp?.post(tap: tapLocation)
            usleep(1500)
        }
    }

    private func tapLocation(for keyPress: KeyPress) -> CGEventTapLocation {
        if keyPress.modifiers == .maskControl, isArrowKey(keyPress.keyCode) {
            return controlArrowTapLocation
        }
        return keyboardTapLocation
    }

    private func isArrowKey(_ keyCode: CGKeyCode) -> Bool {
        (123...126).contains(keyCode)
    }

    private func keyPress(for key: String) -> KeyPress? {
        let parts = key.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, let keyCode = keyCode(for: keyName) else { return nil }

        var modifiers: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command":      modifiers.insert(.maskCommand)
            case "shift":               modifiers.insert(.maskShift)
            case "option", "opt", "alt":modifiers.insert(.maskAlternate)
            case "ctrl", "control":     modifiers.insert(.maskControl)
            default: break
            }
        }

        return KeyPress(keyCode: keyCode, modifiers: modifiers)
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            print("iControl: failed to get default output device: \(status)")
            return nil
        }

        return deviceID
    }

    private func startObservingVolumeChanges() {
        guard let deviceID = defaultOutputDeviceID() else {
            print("iControl: failed to start volume observer")
            return
        }

        observeVolumeProperty(deviceID: deviceID, element: kAudioObjectPropertyElementMain)
        observeVolumeProperty(deviceID: deviceID, element: 1)
        observeVolumeProperty(deviceID: deviceID, element: 2)
    }

    private func observeVolumeProperty(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return }

        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, volumeObserverQueue) { [weak self] _, _ in
            guard let self, let volume = self.currentVolumePercentage() else { return }
            DispatchQueue.main.async {
                self.onVolumeChanged?(volume)
            }
        }

        if status != noErr {
            print("iControl: failed to observe volume changes: \(status)")
        }
    }

    private func systemVolume() -> Float? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }

        if let volume = volumeScalar(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return volume
        }

        return volumeScalar(deviceID: deviceID, element: 1)
            ?? volumeScalar(deviceID: deviceID, element: 2)
    }

    private func setSystemVolume(_ volume: Float) {
        guard let deviceID = defaultOutputDeviceID() else {
            print("iControl: failed to find default output device for volume")
            return
        }

        let clamped = max(0, min(1, volume))
        var didSet = false

        if setVolumeScalar(clamped, deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            didSet = true
        } else {
            let left = setVolumeScalar(clamped, deviceID: deviceID, element: 1)
            let right = setVolumeScalar(clamped, deviceID: deviceID, element: 2)
            didSet = left || right
        }

        if !didSet {
            print("iControl: failed to set output volume")
        }
    }

    private func volumeScalar(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var volume = Float32(0)
        var dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &volume)
        return status == noErr ? volume : nil
    }

    private func setVolumeScalar(_ volume: Float, deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var isSettable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        guard settableStatus == noErr, isSettable.boolValue else { return false }

        var mutableVolume = Float32(volume)
        let dataSize = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &mutableVolume)
        return status == noErr
    }

    private func isSystemMuted(deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var muted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &muted)
        return status == noErr ? muted != 0 : nil
    }

    private func setSystemMuted(_ muted: Bool, deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            print("iControl: output device does not expose mute")
            return
        }

        var isSettable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        guard settableStatus == noErr, isSettable.boolValue else {
            print("iControl: mute is not settable on output device")
            return
        }

        var mutableMuted: UInt32 = muted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, dataSize, &mutableMuted)
        if status != noErr {
            print("iControl: failed to set mute: \(status)")
        }
    }

    private func modifierKeyCodes(for flags: CGEventFlags) -> [CGKeyCode] {
        var keyCodes: [CGKeyCode] = []
        if flags.contains(.maskCommand)  { keyCodes.append(55) }
        if flags.contains(.maskShift)    { keyCodes.append(56) }
        if flags.contains(.maskAlternate){ keyCodes.append(58) }
        if flags.contains(.maskControl)  { keyCodes.append(59) }
        return keyCodes
    }

    private func flags(forPressedModifierKeyCode keyCode: CGKeyCode) -> CGEventFlags {
        switch keyCode {
        case 55: return .maskCommand
        case 56: return .maskShift
        case 58: return .maskAlternate
        case 59: return .maskControl
        default: return []
        }
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        switch key {
        case "space":               return 49
        case "right", "forward":   return 124
        case "left", "back":       return 123
        case "up":                  return 126
        case "down":                return 125
        case "return", "enter":     return 36
        case "escape":              return 53
        case "tab":                 return 48
        case "backspace", "delete": return 51
        default:                    return alphaNumericKeyCode(for: key)
        }
    }

    private func alphaNumericKeyCode(for key: String) -> CGKeyCode? {
        let keyCodes: [String: CGKeyCode] = [
            "a": 0,  "s": 1,  "d": 2,  "f": 3,  "h": 4,
            "g": 5,  "z": 6,  "x": 7,  "c": 8,  "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20,
            "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
            "7": 26, "-": 27, "8": 28, "0": 29, "]": 30,
            "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
            "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47
        ]
        return keyCodes[key]
    }
}

private struct KeyPress {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}
