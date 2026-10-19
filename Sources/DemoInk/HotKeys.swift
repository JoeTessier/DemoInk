import AppKit
import Carbon

/// Global hotkeys via Carbon RegisterEventHotKey: no Accessibility permission, no event tap.
/// One instance = one independent set of registrations (e.g. always-on ⌃⌥ keys vs. drawing-mode-only keys).
final class HotKeyManager {
    struct Registration {
        let name: String
        let status: OSStatus
        var ok: Bool { status == noErr }
    }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var combos = Set<UInt64>()
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x446D496B // 'DmIk'
    private static var nextSignatureSalt: UInt32 = 0

    var count: Int { refs.count }

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr else { return err }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            guard hkID.signature == HotKeyManager.signature, let handler = manager.handlers[hkID.id] else {
                return OSStatus(eventNotHandledErr)
            }
            handler()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr { NSLog("DemoInk: InstallEventHandler failed (%d)", status) }
        // Each manager gets its own id range so two managers' handlers never see each other's ids.
        firstID = HotKeyManager.nextSignatureSalt &* 10_000 &+ 1
        nextID = firstID
        HotKeyManager.nextSignatureSalt += 1
    }

    private var firstID: UInt32 = 1

    /// Registers `keyCode`+`modifiers`. Duplicate combos within this manager are ignored (returns noErr).
    @discardableResult
    func register(name: String, keyCode: UInt32, modifiers: UInt32, quiet: Bool = false,
                  handler: @escaping () -> Void) -> Registration {
        let combo = UInt64(keyCode) << 32 | UInt64(modifiers)
        guard !combos.contains(combo) else { return Registration(name: name, status: noErr) }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: HotKeyManager.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            refs.append(ref)
            handlers[id] = handler
            combos.insert(combo)
            if !quiet { NSLog("DemoInk: hotkey %@ registered (keyCode %u)", name, keyCode) }
        } else {
            NSLog("DemoInk: hotkey %@ registration FAILED (OSStatus %d)", name, status)
        }
        return Registration(name: name, status: status)
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        handlers.removeAll()
        combos.removeAll()
        nextID = firstID // ids are free again: the range never drifts into another manager's
    }

    /// Virtual key code that types `char` in the current keyboard layout (so ⌃⌥A is the key labelled A
    /// on AZERTY too). Falls back to `fallback` (ANSI/QWERTY position).
    static func keyCode(for char: Character, fallback: UInt32) -> UInt32 {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let target = String(char).lowercased()
        return data.withUnsafeBytes { buf -> UInt32 in
            guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return fallback }
            for code in 0..<128 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let st = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &dead, 4, &length, &chars)
                if st == noErr, length > 0,
                   String(utf16CodeUnits: chars, count: length).lowercased() == target {
                    return UInt32(code)
                }
            }
            return fallback
        }
    }
}
