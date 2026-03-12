import AppKit
import CoreAudio
import CoreGraphics
import Foundation

final class InputController {
    var onVolumeChanged: ((Double) -> Void)?

    private let volumeObserverQueue = DispatchQueue(label: "iControl.VolumeObserver")
    private var lastKnownPosition: CGPoint
    private var lastMoveTime: Date = .distantPast

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
            wheel1: Int32(-dy),
            wheel2: Int32(dx),
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    func mouseClick(button: String) {
        postClick(button: button, clickState: 1)
    }

    func doubleClick(button: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let point = lastKnownPosition
        postClick(button: button, clickState: 1, source: source, point: point)
        Thread.sleep(forTimeInterval: 0.05)
        postClick(button: button, clickState: 2, source: source, point: point)
    }

    func tripleClick(button: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let point = lastKnownPosition
        postClick(button: button, clickState: 1, source: source, point: point)
        Thread.sleep(forTimeInterval: 0.05)
        postClick(button: button, clickState: 2, source: source, point: point)
        Thread.sleep(forTimeInterval: 0.05)
        postClick(button: button, clickState: 3, source: source, point: point)
    }

    func pressKey(key: String) {
        if let keyPress = keyPress(for: key) {
            postKeyPress(keyPress)
        } else {
            typeText(string: key)
        }
    }

    func typeText(string: String) {
        guard !string.isEmpty else {
            return
        }

        let utf16 = Array(string.utf16)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)

        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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
//            adjustVolume(by: 0.06)
            postSystemKey(0)
        case "volumeDown":
//            adjustVolume(by: -0.06)
            postSystemKey(1)
        case "mute":
//            toggleMute()
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
        default:
            break
        }
    }

    func currentVolumePercentage() -> Double? {
        guard let volume = systemVolume() else {
            return nil
        }

        return Double(volume * 100)
    }

    func launchApp(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

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

    private func postClick(button: String, clickState: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        let point = lastKnownPosition
        postClick(button: button, clickState: clickState, source: source, point: point)
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

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags = [], tap: CGEventTapLocation = .cghidEventTap) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        if !flags.isEmpty {
            down?.flags = flags
            up?.flags = flags
        }
        down?.post(tap: tap)
        up?.post(tap: tap)
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

    private func adjustVolume(by delta: Float) {
        let current = systemVolume() ?? 0.5
        let next = max(0, min(1, current + delta))
        setSystemVolume(next)
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

        for modifierKeyCode in modifierKeyCodes {
            let modifierDown = CGEvent(keyboardEventSource: nil, virtualKey: modifierKeyCode, keyDown: true)
            modifierDown?.flags = flags(forPressedModifierKeyCode: modifierKeyCode)
            modifierDown?.post(tap: .cghidEventTap)
            usleep(1500)
        }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyPress.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyPress.keyCode, keyDown: false)
        down?.flags = keyPress.modifiers
        up?.flags = keyPress.modifiers
        down?.post(tap: .cghidEventTap)
        usleep(1500)
        up?.post(tap: .cghidEventTap)
        usleep(1500)

        for modifierKeyCode in modifierKeyCodes.reversed() {
            let modifierUp = CGEvent(keyboardEventSource: nil, virtualKey: modifierKeyCode, keyDown: false)
            modifierUp?.flags = []
            modifierUp?.post(tap: .cghidEventTap)
            usleep(1500)
        }
    }

    private func keyPress(for key: String) -> KeyPress? {
        let parts = key.lowercased().split(separator: "+").map(String.init)
        guard let keyName = parts.last, let keyCode = keyCode(for: keyName) else {
            return nil
        }

        var modifiers: CGEventFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "cmd", "command":
                modifiers.insert(.maskCommand)
            case "shift":
                modifiers.insert(.maskShift)
            case "option", "alt":
                modifiers.insert(.maskAlternate)
            case "ctrl", "control":
                modifiers.insert(.maskControl)
            default:
                break
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

        guard AudioObjectHasProperty(deviceID, &address) else {
            return
        }

        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, volumeObserverQueue) { [weak self] _, _ in
            guard let self, let volume = self.currentVolumePercentage() else {
                return
            }

            DispatchQueue.main.async {
                self.onVolumeChanged?(volume)
            }
        }

        if status != noErr {
            print("iControl: failed to observe volume changes: \(status)")
        }
    }

    private func systemVolume() -> Float? {
        guard let deviceID = defaultOutputDeviceID() else {
            return nil
        }

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

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

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

        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var isSettable: DarwinBoolean = false
        let settableStatus = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        guard settableStatus == noErr, isSettable.boolValue else {
            return false
        }

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

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

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

        if flags.contains(.maskCommand) {
            keyCodes.append(55)
        }
        if flags.contains(.maskShift) {
            keyCodes.append(56)
        }
        if flags.contains(.maskAlternate) {
            keyCodes.append(58)
        }
        if flags.contains(.maskControl) {
            keyCodes.append(59)
        }

        return keyCodes
    }

    private func flags(forPressedModifierKeyCode keyCode: CGKeyCode) -> CGEventFlags {
        switch keyCode {
        case 55:
            .maskCommand
        case 56:
            .maskShift
        case 58:
            .maskAlternate
        case 59:
            .maskControl
        default:
            []
        }
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        switch key {
        case "space":
            49
        case "right", "forward":
            124
        case "left", "back":
            123
        case "up":
            126
        case "down":
            125
        case "return", "enter":
            36
        case "escape":
            53
        case "tab":
            48
        case "backspace", "delete":
            51
        case "home":
            115
        case "end":
            119
        case "pageup":
            116
        case "pagedown":
            121
        case "a":
            0
        case "c":
            8
        case "f":
            3
        case "m":
            46
        case "q":
            12
        case "r":
            15
        case "v":
            9
        default:
            nil
        }
    }
}

private struct KeyPress {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}
