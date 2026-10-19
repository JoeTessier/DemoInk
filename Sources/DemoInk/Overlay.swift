import AppKit
import Carbon

final class OverlayPanel: NSPanel {
    let canvas: CanvasView
    let targetScreen: NSScreen

    /// Height of the menu-bar strip to leave uncovered at the top of `screen`. With an auto-hidden menu bar the
    /// strip is 0 on the primary screen: the status-bar thickness is reserved there so the bar can still slide in.
    static func menuBarStrip(for screen: NSScreen) -> CGFloat {
        let strip = screen.frame.maxY - screen.visibleFrame.maxY
        if strip > 0 { return strip }
        return screen == NSScreen.screens.first ? NSStatusBar.system.thickness : 0
    }

    /// The screen minus its menu-bar strip: at `.screenSaver` level the panel would otherwise sit ABOVE the menu
    /// bar (level 24), hide it and swallow clicks on the status item while drawing.
    static func frame(for screen: NSScreen) -> NSRect {
        var f = screen.frame
        f.size.height -= menuBarStrip(for: screen)
        return f
    }

    init(screen: NSScreen) {
        targetScreen = screen
        let frame = OverlayPanel.frame(for: screen)
        canvas = CanvasView(frame: NSRect(origin: .zero, size: frame.size), scale: screen.backingScaleFactor)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(frame, display: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .readOnly // visible to full-screen capture (Zoom/Teams/Meet "share screen")
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        contentView = canvas
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Everything a key can do while drawing. Both input paths (drawing-mode Carbon hotkeys, panel keyDown)
/// map to one of these and go through `OverlayController.perform`, so an action never fires twice.
enum KeyAction: Equatable {
    case exit            // Esc: leave drawing mode AND clear everything (independent of "clear on exit")
    case tool(Tool)
    case color(Int)
    case undo
    case clearAll
    case boardWhite
    case boardBlack
    case widthDown
    case widthUp
}

final class OverlayController {
    private(set) var isDrawing = false
    private(set) var panels: [OverlayPanel] = []
    enum Board { case white, black }
    private var board: Board?
    var onStateChange: (() -> Void)?

    /// Carbon hotkeys that exist ONLY while drawing mode is on (modifier-less: Esc, letters, digits…).
    /// The overlay is a non-activating panel of a never-active app, so plain keyDown never reaches it;
    /// RegisterEventHotKey delivers these keys to us regardless of which app is frontmost, with no
    /// Accessibility permission. They are unregistered the instant drawing mode ends.
    private let modeKeys = HotKeyManager()
    private var lastAction: (KeyAction, TimeInterval)?
    var modeHotKeyCount: Int { modeKeys.count }
    /// Drawing-mode keys whose registration failed (owned by another app); shown in the status menu.
    private(set) var modeKeyFailures: [String] = []
    private var screenSignature = ""
    var panelCount: Int { panels.count }

    init() {
        rebuildPanels()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        if let selftest = ProcessInfo.processInfo.environment["DEMOINK_SELFTEST"] { scheduleSelfTest(selftest) }
    }

    private static func currentScreenSignature() -> String {
        NSScreen.screens.map { "\($0.frame)@\($0.backingScaleFactor)" }.joined(separator: "|")
    }

    /// Display configuration notification. The same notification also fires on sleep/wake, Dock/menu-bar
    /// changes… with an unchanged screen set: then the panels (and the annotations on them) are kept.
    func screensChanged(force: Bool = false) {
        guard force || OverlayController.currentScreenSignature() != screenSignature else {
            panels.forEach { $0.orderFrontRegardless() }
            return
        }
        rebuildPanels()
    }

    private func rebuildPanels() {
        panels.forEach { $0.canvas.cancelCurrent(); $0.orderOut(nil); $0.close() }
        panels = NSScreen.screens.map { screen in
            let p = OverlayPanel(screen: screen)
            p.canvas.controller = self
            p.orderFrontRegardless()
            return p
        }
        screenSignature = OverlayController.currentScreenSignature()
        board = nil
        NSLog("DemoInk: %d overlay panel(s) built", panels.count)
        applyMode() // drawing state, cursor and mode hotkeys are untouched: they do not depend on the panels
    }

    private func scheduleSelfTest(_ selftest: String) {
        if selftest == "1", let p = panelUnderMouse() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runSelfTest(on: p.canvas) }
        } else if selftest == "menubar" {
            // Cycles tool+colour once per second through the hotkey/menu entry points (menu-bar label check).
            // Drawing mode is ON during the cycle (the label only exists then) and OFF at the end (icon only).
            let prev = (Settings.shared.tool, Settings.shared.colorIndex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.setDrawing(true) }
            for (i, t) in Tool.allCases.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i)) {
                    self.selectTool(t); self.selectColor(i % palette.count)
                    NSLog("DemoInk menubar test: %@ / %@", t.shortLabel, palette[i % palette.count].name)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(Tool.allCases.count)) {
                self.selectTool(prev.0); self.selectColor(prev.1)
                self.setDrawing(false)
                NSLog("DemoInk menubar test: drawing mode OFF (icon only)")
            }
        } else if selftest == "arrows", let p = panelUnderMouse() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runArrowGallery(on: p.canvas) }
        } else if selftest == "shapes", let p = panelUnderMouse() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runShapesGallery(on: p.canvas) }
        }
    }

    func panelUnderMouse() -> OverlayPanel? {
        let m = NSEvent.mouseLocation
        return panels.first { NSMouseInRect(m, $0.targetScreen.frame, false) } ?? panels.first
    }

    // MARK: Mode

    func toggle() { setDrawing(!isDrawing) }

    /// `clearAll`: nil → follow the "clear on exit" setting (⌃⌥A / menu); true → always clear (Esc).
    func setDrawing(_ on: Bool, clearAll forceClear: Bool? = nil) {
        guard on != isDrawing else { return }
        isDrawing = on
        if on {
            registerModeKeys()
        } else {
            modeKeys.unregisterAll()
            modeKeyFailures = []
            panels.forEach { $0.canvas.cancelCurrent() } // Esc mid-drag: drop the in-progress stroke
            setBoard(nil)
            if forceClear ?? Settings.shared.clearOnExit { panels.forEach { $0.canvas.clear() } }
        }
        applyMode()
        NSLog("DemoInk: drawing mode %@ (mode hotkeys: %d, layers on screen: %d)", on ? "ON" : "OFF", modeKeys.count,
              panels.reduce(0) { $0 + $1.canvas.layerCount })
        onStateChange?()
    }

    private func applyMode() {
        for p in panels {
            p.ignoresMouseEvents = !isDrawing
            p.invalidateCursorRects(for: p.canvas)
        }
        if isDrawing {
            if let p = panelUnderMouse() {
                p.makeKeyAndOrderFront(nil)
                p.makeFirstResponder(p.canvas)
            }
            NSCursor.crosshair.set()
        } else {
            // Drop key status so keyboard focus returns to the presented app (which never stopped being active).
            for p in panels where p.isKeyWindow {
                p.orderOut(nil)
                p.orderFrontRegardless()
            }
            NSCursor.arrow.set()
        }
    }

    // MARK: Actions

    func clearAll() {
        board = nil
        panels.forEach { $0.canvas.clear() }
    }

    func undoUnderMouse() { panelUnderMouse()?.canvas.undo() }

    /// Number for the next Count marker. Global across screens and derived from the markers on screen,
    /// so undo (removes the last marker) decrements it and any clear resets it to 1 with no extra state.
    func nextMarkerNumber() -> Int { (panels.map { $0.canvas.maxMarkerNumber }.max() ?? 0) + 1 }

    func selectTool(_ t: Tool) {
        Settings.shared.tool = t
        onStateChange?() // menu-bar label is the feedback (no HUD)
    }

    func selectColor(_ i: Int) {
        guard palette.indices.contains(i) else { return }
        Settings.shared.colorIndex = i
        panels.forEach { $0.canvas.refreshCurrent() } // in-progress stroke switches colour instantly
        onStateChange?() // menu-bar colour dot is the feedback (no HUD)
    }

    func changeWidth(by delta: CGFloat) {
        let s = Settings.shared
        let w = min(max(s.width + delta, Settings.minWidth), Settings.maxWidth)
        guard w != s.width else { showHUD("Épaisseur \(Int(w)) pt"); return }
        s.width = w
        panels.forEach { $0.canvas.refreshCurrent() }
        showHUD("Épaisseur \(Int(w)) pt")
    }

    func setBoard(_ b: Board?) {
        board = b
        let color: NSColor? = b.map { $0 == .white ? .white : NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1) }
        panels.forEach { $0.canvas.setBoard(color) }
    }

    func contentChanged() {}

    /// On-screen toast. Only used for stroke-width changes (tool/colour are shown in the menu bar).
    func showHUD(_ text: String) { panelUnderMouse()?.canvas.showHUD(text) }

    // MARK: Keyboard — single dispatch point for both input paths

    /// Executes a drawing-mode key action. Ignored outside drawing mode. The same action arriving from the
    /// two paths within 50 ms (hotkey + panel keyDown) is executed once.
    @discardableResult
    func perform(_ action: KeyAction, source: String) -> Bool {
        guard isDrawing else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        if let (a, t) = lastAction, a == action, now - t < 0.05 {
            NSLog("DemoInk: key action %@ via %@ deduplicated", String(describing: action), source)
            return true
        }
        lastAction = (action, now)
        NSLog("DemoInk: key action %@ via %@", String(describing: action), source)
        switch action {
        case .exit: setDrawing(false, clearAll: true)
        case .tool(let t): selectTool(t)
        case .color(let i): selectColor(i)
        case .undo: undoUnderMouse()
        case .clearAll: clearAll()
        case .boardWhite: setBoard(board == .white ? nil : .white)
        case .boardBlack: setBoard(board == .black ? nil : .black)
        case .widthDown: changeWidth(by: -1)
        case .widthUp: changeWidth(by: 1)
        }
        return true
    }

    /// Fallback path: the key panel's canvas got a real keyDown (only happens if the panel somehow has focus).
    func handleKey(_ e: NSEvent) -> Bool {
        guard isDrawing, let action = OverlayController.action(for: e) else { return false }
        return perform(action, source: "panel")
    }

    static func action(for e: NSEvent) -> KeyAction? {
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if e.keyCode == UInt16(kVK_Escape) { return .exit }
        if flags.contains(.command) { return chars == "z" ? .undo : nil }
        if flags.contains(.control) { return nil }
        // Digits by physical key (works on AZERTY where 1–5 need Shift) and by character (numpad).
        let digitCodes: [UInt16: Int] = [UInt16(kVK_ANSI_1): 0, UInt16(kVK_ANSI_2): 1, UInt16(kVK_ANSI_3): 2,
                                         UInt16(kVK_ANSI_4): 3, UInt16(kVK_ANSI_5): 4,
                                         UInt16(kVK_ANSI_Keypad1): 0, UInt16(kVK_ANSI_Keypad2): 1,
                                         UInt16(kVK_ANSI_Keypad3): 2, UInt16(kVK_ANSI_Keypad4): 3,
                                         UInt16(kVK_ANSI_Keypad5): 4]
        if let i = digitCodes[e.keyCode] { return .color(i) }
        if let c = chars.first, let d = c.wholeNumberValue, (1...5).contains(d) { return .color(d - 1) }
        if e.keyCode == UInt16(kVK_ANSI_LeftBracket) || ["[", "-", "_"].contains(chars) { return .widthDown }
        if e.keyCode == UInt16(kVK_ANSI_RightBracket) || ["]", "+", "="].contains(chars) { return .widthUp }
        switch chars {
        case "z": return .undo
        case "c", "e": return .clearAll
        case "w": return .boardWhite
        case "k": return .boardBlack
        default: return Tool.allCases.first(where: { $0.key == chars }).map { .tool($0) }
        }
    }

    /// Keyboard layout changed (AZERTY ⇄ QWERTY…): letters are registered by layout, so rebuild them.
    func keyboardLayoutChanged() {
        guard isDrawing else { return }
        modeKeys.unregisterAll()
        registerModeKeys()
    }

    private func registerModeKeys() {
        modeKeys.unregisterAll()
        let shift = UInt32(shiftKey)
        var failed: [String] = []
        func reg(_ name: String, _ code: UInt32, _ mods: UInt32, _ action: KeyAction) {
            let r = modeKeys.register(name: name, keyCode: code, modifiers: mods, quiet: true) { [weak self] in
                self?.perform(action, source: "hotkey")
            }
            if !r.ok { failed.append(name) }
        }
        /// Letter in the current layout, with and without ⇧ (so Caps/Shift do not break it).
        func letter(_ ch: Character, _ fallback: Int, _ action: KeyAction) {
            let code = HotKeyManager.keyCode(for: ch, fallback: UInt32(fallback))
            reg(String(ch), code, 0, action)
            reg("⇧" + String(ch), code, shift, action)
        }

        // Esc must always exit, whatever modifier happens to be held (⇧/⌘/⌥/⌃ in any mix). Carbon matches
        // modifiers exactly, so every combination is registered — except those containing ⌘⌥ (Force Quit).
        let modBits: [(UInt32, String)] = [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"),
                                           (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
        for mask in 0..<16 {
            var mods: UInt32 = 0, name = ""
            for (i, (bit, sym)) in modBits.enumerated() where mask & (1 << i) != 0 { mods |= bit; name += sym }
            if mods & UInt32(cmdKey | optionKey) == UInt32(cmdKey | optionKey) { continue }
            reg(name + "Esc", UInt32(kVK_Escape), mods, .exit)
        }
        for t in Tool.allCases {
            let fb: Int
            switch t { case .arrow: fb = kVK_ANSI_A; case .rectangle: fb = kVK_ANSI_R; case .highlighter: fb = kVK_ANSI_H
                       case .spotlight: fb = kVK_ANSI_S; case .pen: fb = kVK_ANSI_P
                       case .oval: fb = kVK_ANSI_O; case .counter: fb = kVK_ANSI_N }
            letter(Character(t.key), fb, .tool(t))
        }
        letter("z", kVK_ANSI_Z, .undo)
        reg("⌘Z", HotKeyManager.keyCode(for: "z", fallback: UInt32(kVK_ANSI_Z)), UInt32(cmdKey), .undo)
        letter("c", kVK_ANSI_C, .clearAll)
        letter("e", kVK_ANSI_E, .clearAll)
        letter("w", kVK_ANSI_W, .boardWhite)
        letter("k", kVK_ANSI_K, .boardBlack)
        // Colours: physical top-row digit keys (AZERTY needs no ⇧, but accept it), plus numpad.
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        let keypad = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5]
        for (i, code) in digits.enumerated() {
            reg("\(i + 1)", UInt32(code), 0, .color(i))
            reg("⇧\(i + 1)", UInt32(code), shift, .color(i))
        }
        for (i, code) in keypad.enumerated() { reg("pavé \(i + 1)", UInt32(code), 0, .color(i)) }
        // Width: - / + (and _ / = on the same keys), [ / ], numpad - / +.
        let minus = HotKeyManager.keyCode(for: "-", fallback: UInt32(kVK_ANSI_Minus))
        let equal = HotKeyManager.keyCode(for: "=", fallback: UInt32(kVK_ANSI_Equal))
        reg("-", minus, 0, .widthDown); reg("⇧-", minus, shift, .widthDown)
        reg("=", equal, 0, .widthUp);   reg("+", equal, shift, .widthUp)
        reg("[", HotKeyManager.keyCode(for: "[", fallback: UInt32(kVK_ANSI_LeftBracket)), 0, .widthDown)
        reg("]", HotKeyManager.keyCode(for: "]", fallback: UInt32(kVK_ANSI_RightBracket)), 0, .widthUp)
        reg("pavé -", UInt32(kVK_ANSI_KeypadMinus), 0, .widthDown)
        reg("pavé +", UInt32(kVK_ANSI_KeypadPlus), 0, .widthUp)

        modeKeyFailures = failed
        NSLog("DemoInk: %d drawing-mode hotkeys registered, %d failed", modeKeys.count, failed.count)
    }

    /// App termination: leave drawing mode so the modifier-less hotkeys are released and the cursor restored.
    func terminate() {
        setDrawing(false)
        modeKeys.unregisterAll()
    }
}
