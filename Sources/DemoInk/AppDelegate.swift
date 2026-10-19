import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlay: OverlayController!
    private let hotKeys = HotKeyManager()
    private var hotKeyResults: [HotKeyManager.Registration] = []
    private let mods = UInt32(controlKey | optionKey)
    /// "Suspendre les raccourcis": every global hotkey released (and drawing mode left) until re-enabled.
    private var hotKeysPaused = false
    var globalHotKeyCount: Int { hotKeys.count }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = OverlayController()
        overlay.onStateChange = { [weak self] in self?.updateIcon() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        registerHotKeys()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main) { [weak self] _ in
                self?.registerHotKeys()
                self?.overlay.keyboardLayoutChanged()
            }
        NSLog("DemoInk: launched — toggle drawing mode with ⌃§ (keyCode %d + control), fallback ⌃⌥A", kVK_ISO_Section)
    }

    /// Quit (menu, ⌘Q from the menu, logout): release the drawing-mode keys and the cursor before the process goes.
    func applicationWillTerminate(_ notification: Notification) {
        overlay?.terminate()
        hotKeys.unregisterAll()
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        hotKeyResults = []
        guard !hotKeysPaused else { return }
        let a = HotKeyManager.keyCode(for: "a", fallback: UInt32(kVK_ANSI_A))
        let c = HotKeyManager.keyCode(for: "c", fallback: UInt32(kVK_ANSI_C))
        var results: [HotKeyManager.Registration] = []
        // Primary toggle: ⌃§ — the physical ISO top-left key (kVK_ISO_Section = 10), never mapped by layout.
        results.append(hotKeys.register(name: "⌃§", keyCode: UInt32(kVK_ISO_Section), modifiers: UInt32(controlKey)) { [weak self] in
            self?.overlay.toggle()
        })
        // Secondary toggle (free fallback, e.g. ANSI keyboards without a § key).
        results.append(hotKeys.register(name: "⌃⌥A", keyCode: a, modifiers: mods) { [weak self] in self?.overlay.toggle() })
        results.append(hotKeys.register(name: "⌃⌥C", keyCode: c, modifiers: mods) { [weak self] in self?.overlay.clearAll() })
        // Colours: physical top-row digit keys (layout independent, AZERTY-safe).
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        for (i, code) in digits.enumerated() {
            results.append(hotKeys.register(name: "⌃⌥\(i + 1)", keyCode: UInt32(code), modifiers: mods) { [weak self] in
                self?.overlay.selectColor(i)
            })
        }
        hotKeyResults = results
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let s = Settings.shared
        let name = overlay.isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "DemoInk")
            ?? NSImage(systemSymbolName: "pencil", accessibilityDescription: "DemoInk")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        if overlay.isDrawing {
            button.attributedTitle = statusTitle(tool: s.tool, color: s.color.color)
            // Fixed width = widest tool label, so the item never jumps when the tool changes.
            let widest = Tool.allCases.map { statusTitle(tool: $0, color: .black).size().width }.max() ?? 0
            statusItem.length = ceil(widest + (img?.size.width ?? 16) + 14)
        } else {
            // Drawing mode off: icon only, no tool label or colour dot.
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.squareLength
        }
        button.toolTip = (overlay.isDrawing ? "DemoInk — mode dessin actif" : "DemoInk") + " · \(s.tool.label) · \(s.color.name)"
    }

    /// " Arrow ●" — tool label in the menu-bar font, followed by a dot in the current ink colour.
    private func statusTitle(tool: Tool, color: NSColor) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let t = NSMutableAttributedString(string: " " + tool.shortLabel, attributes: [.font: font])
        let dotFont = NSFont.systemFont(ofSize: font.pointSize * 0.8)
        t.append(NSAttributedString(string: " ●", attributes: [
            .font: dotFont, .foregroundColor: color,
            .baselineOffset: (font.capHeight - dotFont.capHeight) / 2]))
        return t
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared

        let toggle = item(overlay.isDrawing ? "Quitter le mode dessin  ⌃§" : "Mode dessin  ⌃§", #selector(toggleDrawing))
        toggle.state = overlay.isDrawing ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())

        for (i, t) in Tool.allCases.enumerated() {
            let it = item("\(t.label)  (\(t.key.uppercased()))", #selector(chooseTool(_:)))
            it.tag = i
            it.state = s.tool == t ? .on : .off
            it.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.label)
            menu.addItem(it)
        }
        menu.addItem(.separator())
        for (i, c) in palette.enumerated() {
            let it = item("\(c.name)  (\(i + 1))", #selector(chooseColor(_:)))
            it.tag = i
            it.state = s.colorIndex == i ? .on : .off
            it.image = swatch(c.color)
            menu.addItem(it)
        }
        menu.addItem(.separator())
        menu.addItem(item("Tout effacer  ⌃⌥C", #selector(clearAll)))
        let coe = item("Effacer en quittant le mode dessin", #selector(toggleClearOnExit))
        coe.state = s.clearOnExit ? .on : .off
        menu.addItem(coe)
        menu.addItem(.separator())

        let pause = item("Suspendre les raccourcis globaux", #selector(togglePause))
        pause.state = hotKeysPaused ? .on : .off
        menu.addItem(pause)
        let failed = hotKeyResults.filter { !$0.ok }
        var text = hotKeysPaused ? "Raccourcis globaux : suspendus" : failed.isEmpty ? "Raccourcis globaux : OK"
            : "⚠︎ Raccourci(s) indisponible(s) : " + failed.map { "\($0.name) (\($0.status))" }.joined(separator: ", ")
        if !overlay.modeKeyFailures.isEmpty {
            text += " · ⚠︎ touches dessin indisponibles : " + overlay.modeKeyFailures.joined(separator: ", ")
        }
        let status = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let quit = item("Quitter DemoInk", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    private func swatch(_ color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).stroke()
            return true
        }
        img.isTemplate = false
        return img
    }

    @objc private func toggleDrawing() { overlay.toggle() }
    @objc private func chooseTool(_ sender: NSMenuItem) { overlay.selectTool(Tool.allCases[sender.tag]) }
    @objc private func chooseColor(_ sender: NSMenuItem) { overlay.selectColor(sender.tag) }
    @objc private func clearAll() { overlay.clearAll() }
    @objc private func toggleClearOnExit() { Settings.shared.clearOnExit.toggle() }
    @objc private func togglePause() {
        hotKeysPaused.toggle()
        if hotKeysPaused { overlay.setDrawing(false) }
        registerHotKeys()
        NSLog("DemoInk: global hotkeys %@ (%d registered)", hotKeysPaused ? "paused" : "resumed", hotKeys.count)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
