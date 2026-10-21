import AppKit

/// DEMOINK_SELFTEST=arrows: draws a gallery of arrows (widths 2/4/10/24, 8 directions, short drags) and stays
/// in drawing mode so the junctions can be screen-captured. DEMOINK_BOARD=white|black puts a board behind them.
///
/// Developer smoke test (DEMOINK_SELFTEST=1): enters drawing mode and feeds synthetic mouse events
/// to the canvas under the mouse, one gesture per tool, to exercise geometry + rendering without a human.
/// Then exercises the keyboard state machine through the same `perform` entry point the Carbon hotkeys use.
extension OverlayController {
    func runArrowGallery(on canvas: CanvasView) {
        guard let window = canvas.window else { return }
        setDrawing(true)
        switch ProcessInfo.processInfo.environment["DEMOINK_BOARD"] {
        case "white": setBoard(.white)
        case "black": setBoard(.black)
        default: break
        }
        let prevWidth = Settings.shared.width, prevTool = Settings.shared.tool, prevColor = Settings.shared.colorIndex
        func ev(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        selectTool(.arrow)
        let b = canvas.bounds
        let widths: [CGFloat] = [2, 4, 10, 24]
        for (row, w) in widths.enumerated() {
            Settings.shared.width = w
            let cy = b.maxY - 160 - CGFloat(row) * 190
            for k in 0..<8 {
                selectColor((row + k) % palette.count)
                let c = CGPoint(x: 140 + CGFloat(k) * 170, y: cy)
                let a = CGFloat(k) * .pi / 4
                let s = CGPoint(x: c.x - cos(a) * 65, y: c.y - sin(a) * 65)
                let e = CGPoint(x: c.x + cos(a) * 65, y: c.y + sin(a) * 65)
                canvas.mouseDown(with: ev(.leftMouseDown, s))
                canvas.mouseDragged(with: ev(.leftMouseDragged, e))
                canvas.mouseUp(with: ev(.leftMouseUp, e))
            }
            // Short drags: 4, 8, 15, 30 pt.
            for (j, l) in ([4, 8, 15, 30] as [CGFloat]).enumerated() {
                let s = CGPoint(x: 1560 + CGFloat(j) * 60, y: cy)
                canvas.mouseDown(with: ev(.leftMouseDown, s))
                canvas.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: s.x + l, y: s.y)))
                canvas.mouseUp(with: ev(.leftMouseUp, CGPoint(x: s.x + l, y: s.y)))
            }
        }
        Settings.shared.width = prevWidth
        Settings.shared.tool = prevTool
        Settings.shared.colorIndex = prevColor
        onStateChange?()
        NSLog("DemoInk arrow gallery: %d layers drawn", canvas.layerCount)
    }

    func runSelfTest(on canvas: CanvasView) {
        guard let window = canvas.window else { return }
        let activeAtStart = NSApp.isActive
        NSLog("DemoInk selftest: active at start: %d, frontmost: %@", activeAtStart ? 1 : 0,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")
        let saved = (Settings.shared.tool, Settings.shared.colorIndex, Settings.shared.width, Settings.shared.clearOnExit,
                     Settings.shared.laserColorIndex)
        defer { Settings.shared.tool = saved.0; Settings.shared.colorIndex = saved.1; Settings.shared.width = saved.2
                Settings.shared.clearOnExit = saved.3; Settings.shared.laserColorIndex = saved.4
                onStateChange?() }
        setDrawing(true)
        func ev(_ type: NSEvent.EventType, _ p: CGPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func gesture(_ tool: Tool, _ pts: [CGPoint], color: Int, flags: NSEvent.ModifierFlags = [], recolorMidway: Int? = nil) {
            selectTool(tool)
            selectColor(color)
            canvas.mouseDown(with: ev(.leftMouseDown, pts[0], flags))
            for (i, p) in pts.dropFirst().enumerated() {
                if let r = recolorMidway, i == pts.count / 2 { selectColor(r) }
                canvas.mouseDragged(with: ev(.leftMouseDragged, p, flags))
            }
            canvas.mouseUp(with: ev(.leftMouseUp, pts.last!, flags))
        }
        let b = canvas.bounds
        let cx = b.midX, cy = b.midY
        gesture(.arrow, [CGPoint(x: cx - 400, y: cy + 200), CGPoint(x: cx - 300, y: cy + 150), CGPoint(x: cx - 200, y: cy + 100)], color: 0)
        gesture(.rectangle, [CGPoint(x: cx - 100, y: cy + 50), CGPoint(x: cx + 150, y: cy + 220)], color: 4)
        gesture(.pen, (0..<40).map { CGPoint(x: cx - 400 + CGFloat($0) * 10, y: cy - 150 + sin(CGFloat($0) / 4) * 40) },
                color: 3, recolorMidway: 1)
        gesture(.highlighter, (0..<30).map { CGPoint(x: cx + 50 + CGFloat($0) * 10, y: cy - 60) }, color: 2)
        gesture(.pen, [CGPoint(x: cx + 250, y: cy - 250), CGPoint(x: cx + 420, y: cy - 150)], color: 0, flags: [.option]) // ⌥ → arrow
        gesture(.spotlight, [CGPoint(x: cx - 450, y: cy - 300), CGPoint(x: cx + 450, y: cy + 280)], color: 0)
        changeWidth(by: 2)
        NSLog("DemoInk selftest: drawing=%d hasContent=%d layers=%d", isDrawing ? 1 : 0, canvas.hasContent ? 1 : 0, canvas.layerCount)

        var ok = true
        func check(_ cond: Bool, _ what: String) {
            NSLog("DemoInk selftest: %@ %@", cond ? "PASS" : "FAIL", what)
            ok = ok && cond
        }

        // Oval / circle.
        var n0 = canvas.layerCount
        gesture(.oval, [CGPoint(x: cx - 300, y: cy + 250), CGPoint(x: cx - 100, y: cy + 330)], color: 1)
        gesture(.oval, [CGPoint(x: cx + 200, y: cy + 250), CGPoint(x: cx + 300, y: cy + 300)], color: 4, flags: [.shift])
        check(canvas.layerCount == n0 + 2, "O draws an oval and a ⇧ circle")
        n0 = canvas.layerCount
        gesture(.oval, [CGPoint(x: cx, y: cy), CGPoint(x: cx + 1, y: cy)], color: 1)
        check(canvas.layerCount == n0, "a tiny oval drag is discarded")

        // Arrows above every other shape: arrow, rectangle, pen, highlighter, ⌥-pen arrow, ovals were drawn in that order.
        let z = (canvas.shapesContainer.sublayers ?? []).map(\.zPosition)
        check(z.count >= 6 && z[0] == 1 && z[4] == 1 && [1, 2, 3].allSatisfy { z[$0] == 0 } && z[5...].allSatisfy { $0 == 0 },
              "arrows (incl. ⌥ override) render above shapes drawn after them (zPosition \(z))")

        // Count markers 1…12, including near every screen edge and corner.
        clearAll()
        check(nextMarkerNumber() == 1, "Count starts at 1")
        let spots: [CGPoint] = [
            CGPoint(x: cx - 300, y: cy), CGPoint(x: cx - 200, y: cy), CGPoint(x: cx - 100, y: cy),
            CGPoint(x: b.minX + 3, y: cy), CGPoint(x: b.maxX - 3, y: cy),             // left / right edges
            CGPoint(x: cx, y: b.maxY - 3), CGPoint(x: cx, y: b.minY + 3),             // top / bottom edges
            CGPoint(x: b.maxX - 3, y: b.maxY - 3), CGPoint(x: b.minX + 3, y: b.minY + 3),
            CGPoint(x: b.minX + 3, y: b.maxY - 3), CGPoint(x: b.maxX - 3, y: b.minY + 3),
            CGPoint(x: cx + 100, y: cy),
        ]
        for (i, p) in spots.enumerated() { gesture(.counter, [p], color: i % palette.count) }
        check(canvas.markerCount == 12 && canvas.maxMarkerNumber == 12 && nextMarkerNumber() == 13, "N places markers 1…12")
        n0 = canvas.layerCount
        gesture(.counter, [CGPoint(x: cx - 200, y: cy - 200), CGPoint(x: cx - 50, y: cy - 120)], color: 0, flags: [.command])
        check(canvas.layerCount == n0 + 1 && nextMarkerNumber() == 13, "⌘-drag from Count draws a rectangle, no marker")
        gesture(.counter, [CGPoint(x: cx + 50, y: cy - 200), CGPoint(x: cx + 200, y: cy - 120)], color: 0, flags: [.option])
        check(canvas.layerCount == n0 + 2 && nextMarkerNumber() == 13, "⌥-drag from Count draws an arrow, no marker")
        undoUnderMouse(); undoUnderMouse() // drop the ⌘/⌥ shapes
        perform(.undo, source: "selftest")
        check(canvas.markerCount == 11 && nextMarkerNumber() == 12, "undo removes marker 12, next is 12")
        gesture(.counter, [CGPoint(x: cx + 200, y: cy)], color: 2)
        check(canvas.maxMarkerNumber == 12 && nextMarkerNumber() == 13, "re-placed marker is 12")
        perform(.clearAll, source: "selftest")
        check(canvas.markerCount == 0 && nextMarkerNumber() == 1, "clear resets Count to 1")
        gesture(.counter, [CGPoint(x: cx, y: cy)], color: 0)
        check(canvas.maxMarkerNumber == 1, "first marker after clear is 1")

        // Keyboard state machine (same entry point as the drawing-mode Carbon hotkeys).
        check(perform(.tool(.oval), source: "selftest") && Settings.shared.tool == .oval, "O selects oval in drawing mode")
        check(perform(.tool(.counter), source: "selftest") && Settings.shared.tool == .counter, "N selects Count in drawing mode")
        check(perform(.tool(.rectangle), source: "selftest") && Settings.shared.tool == .rectangle, "R selects rectangle in drawing mode")
        check(perform(.boardWhite, source: "selftest") && canvas.layerCount > 0, "W shows the white board")
        // Esc mid-drag: start a stroke, do not release the mouse, then Esc.
        selectTool(.pen)
        canvas.mouseDown(with: ev(.leftMouseDown, CGPoint(x: cx, y: cy)))
        canvas.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: cx + 80, y: cy + 40)))
        let before = canvas.layerCount
        check(perform(.exit, source: "selftest"), "Esc handled while dragging (\(before) layers before)")
        canvas.mouseUp(with: ev(.leftMouseUp, CGPoint(x: cx + 100, y: cy + 50))) // late mouseUp must be a no-op
        check(!isDrawing, "drawing mode is OFF after Esc")
        check(canvas.layerCount == 0 && !canvas.hasContent, "canvas has 0 layers after Esc (strokes, spotlight, board cleared)")
        check(modeHotKeyCount == 0, "0 drawing-mode hotkeys registered after Esc (R/Esc… no longer swallowed)")
        check(!perform(.tool(.arrow), source: "selftest"), "R is NOT handled outside drawing mode")
        check(Settings.shared.tool == .pen, "tool unchanged by the ignored key")
        check(nextMarkerNumber() == 1, "Esc resets Count to 1")

        // Pen performance: the smoothed path is rebuilt per mouse event; a long 120 Hz stroke must stay cheap.
        let longStroke = (0..<1200).map { CGPoint(x: cx - 600 + CGFloat($0), y: cy + sin(CGFloat($0) / 9) * 30) }
        let t0 = ProcessInfo.processInfo.systemUptime
        _ = Geometry.smoothPath(longStroke)
        let msPath = (ProcessInfo.processInfo.systemUptime - t0) * 1000
        setDrawing(true)
        let t1 = ProcessInfo.processInfo.systemUptime
        gesture(.pen, longStroke, color: 0)
        let msStroke = (ProcessInfo.processInfo.systemUptime - t1) * 1000
        check(msPath < 5 && msStroke < 1000,
              String(format: "pen: smoothPath(1200 pts) %.2f ms, 1200 drag events %.0f ms total (%.2f ms/event)", msPath, msStroke, msStroke / 1200))

        // Text tool: hotkeys suspended during the entry, focus handed back, undo / clear / Esc / ⌃§ / edges / wheel.
        let front0 = NSWorkspace.shared.frontmostApplication
        let frontName = front0?.bundleIdentifier ?? front0?.localizedName ?? "?"
        func spin(_ seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.02))) }
        }
        func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) {
            let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                     isARepeat: false, keyCode: code)!
            canvas.keyDown(with: e)
        }
        func click(_ p: CGPoint) {
            canvas.mouseDown(with: ev(.leftMouseDown, p))
            canvas.mouseUp(with: ev(.leftMouseUp, p))
        }
        func type(_ s: String) { canvas.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        func frontRestored() -> Bool {
            spin(0.7)
            return NSWorkspace.shared.frontmostApplication == front0
        }
        Settings.shared.clearOnExit = false
        Settings.shared.width = 8
        let nMode = modeHotKeyCount
        check(perform(.tool(.text), source: "selftest") && Settings.shared.tool == .text, "T selects Text in drawing mode")
        let texts0 = canvas.textCount, layers0 = canvas.layerCount
        click(CGPoint(x: cx - 300, y: cy + 100))
        check(isEditingText && modeHotKeyCount == 0, "starting a label suspends every drawing-mode hotkey (0 registered, \(nMode) before)")
        spin(0.5)
        let frontDuring = NSWorkspace.shared.frontmostApplication
        check(frontDuring == NSRunningApplication.current && NSApp.isActive && canvas.window?.isKeyWindow == true
              && canvas.window?.firstResponder === canvas,
              "during the entry: DemoInk frontmost (\(frontDuring?.bundleIdentifier ?? "?")), panel key, editor first responder")
        check(abs((canvas.textEntry?.fontSize ?? 0) - 28) < 0.01, "label size 28 pt at width 8")
        type("Hello")
        key(36, "\r", .shift)                      // ⇧Return: new line
        type("World!!")
        key(51, "\u{7F}")                          // Backspace
        key(123, "\u{F702}", [.function, .numericPad]) // ←
        type("_")
        let edited = canvas.textEntry?.string ?? "nil"
        check(edited == "Hello\nWorld_!", "typing + ⇧Return + Backspace + ← give \"Hello\\nWorld_!\" (got \(edited.debugDescription))")
        let f2 = canvas.textEntry?.layout?.frame ?? .zero
        check(f2.height >= 2 * 28 && f2.width > 60, "label grows in width and height (\(Int(f2.width))x\(Int(f2.height)))")
        key(36, "\r")                               // Return: commit
        check(!isEditingText && isDrawing && modeHotKeyCount == nMode && canvas.textCount == texts0 + 1
              && canvas.layerCount == layers0 + 1,
              "Return commits ONE static layer (no ghost) and restores the \(nMode) hotkeys (now \(modeHotKeyCount))")
        check(frontRestored(), "after the entry, the previously frontmost app (\(frontName)) is frontmost again")
        perform(.undo, source: "selftest")
        check(canvas.textCount == texts0 && canvas.layerCount == layers0, "Z removes the label")

        click(CGPoint(x: cx - 300, y: cy + 100)); type("tmp")
        key(53, "\u{1B}")                           // Esc during the entry
        check(!isEditingText && isDrawing && modeHotKeyCount == nMode && canvas.textCount == texts0
              && canvas.layerCount == layers0, "Esc cancels the entry, drops the label, drawing mode stays on, hotkeys restored")
        check(frontRestored(), "focus restored after a cancelled entry")
        click(CGPoint(x: cx, y: cy)); key(36, "\r")
        check(!isEditingText && canvas.layerCount == layers0 && modeHotKeyCount == nMode, "an empty label is not kept")
        click(CGPoint(x: cx - 200, y: cy)); type("Click")
        click(CGPoint(x: cx + 200, y: cy - 100))
        check(!isEditingText && canvas.textCount == texts0 + 1 && modeHotKeyCount == nMode,
              "a click elsewhere commits (and does not start another label)")

        click(CGPoint(x: cx - 200, y: cy - 200)); type("Big")
        let fs0 = canvas.textEntry?.fontSize ?? 0, layersBeforeWheel = canvas.layerCount
        if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0),
           let wheel = NSEvent(cgEvent: cg) { canvas.scrollWheel(with: wheel) }
        let fs1 = canvas.textEntry?.fontSize ?? 0
        check(isEditingText && fs1 > fs0 && canvas.layerCount == layersBeforeWheel,
              "wheel during the entry resizes the label (\(fs0) → \(fs1) pt), no stroke drawn")
        key(36, "\r")

        click(CGPoint(x: b.maxX - 3, y: b.minY + 3)); type("Near the bottom-right corner\nsecond line\nthird line")
        let fe = canvas.textEntry?.layout?.frame ?? .zero
        check(b.insetBy(dx: 5, dy: 5).contains(fe), "label near the bottom-right edge shifts to stay on screen (\(fe))")
        key(36, "\r")
        let textsNow = canvas.textCount
        perform(.clearAll, source: "selftest")
        check(textsNow >= 3 && canvas.textCount == 0, "C clears the \(textsNow) labels")

        click(CGPoint(x: cx, y: cy)); type("Toggle")
        toggle()                                      // ⌃§ while typing
        check(!isDrawing && !isEditingText && modeHotKeyCount == 0 && canvas.textCount == 1,
              "⌃§ while typing commits the label, then leaves drawing mode with 0 hotkeys")
        check(frontRestored(), "focus restored after ⌃§ mid-entry")
        setDrawing(true)
        click(CGPoint(x: cx, y: cy - 60)); type("x")
        key(53, "\u{1B}")                           // 1st Esc: cancel the entry only
        check(isDrawing && !isEditingText && canvas.textCount == 1, "1st Esc cancels the entry only")
        perform(.exit, source: "selftest")           // 2nd Esc: the drawing-mode hotkey again
        check(!isDrawing && canvas.textCount == 0 && modeHotKeyCount == 0, "2nd Esc exits drawing mode and clears the labels")
        check(frontRestored(), "focus restored after the Esc sequence")
        setDrawing(true)

        // Hotkey lifecycle: every exit path releases the modifier-less keys; re-entry never leaks or duplicates.
        let n = modeHotKeyCount
        check(n > 0 && modeKeyFailures.isEmpty, "\(n) drawing-mode hotkeys registered, none failed")
        keyboardLayoutChanged()
        check(isDrawing && modeHotKeyCount == n, "keyboard layout change re-registers the same \(n) keys (no duplicates)")
        toggle()
        check(!isDrawing && modeHotKeyCount == 0, "⌃§ toggle releases every drawing-mode key")
        keyboardLayoutChanged()
        check(modeHotKeyCount == 0, "layout change outside drawing mode registers nothing")
        setDrawing(true); setDrawing(false); setDrawing(true)
        check(isDrawing && modeHotKeyCount == n, "rapid on/off/on: \(n) keys, no leak")
        check(NSApp.isActive == activeAtStart,
              "drawing mode did not change the app's active state (active at start: \(activeAtStart), now: \(NSApp.isActive), frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"))")

        // Panels: below the menu-bar strip (status item stays clickable while drawing), visible to screen capture.
        for p in panels {
            let s = p.targetScreen
            let strip: CGFloat = s.frame.maxY - p.frame.maxY
            let menuBar: CGFloat = OverlayPanel.menuBarStrip(for: s)
            let sameBottom = p.frame.minY == s.frame.minY && p.frame.minX == s.frame.minX && p.frame.width == s.frame.width
            check(sameBottom && strip == menuBar && (strip > 0 || s != NSScreen.screens.first),
                  "panel \(Int(s.frame.width))x\(Int(s.frame.height)) stops \(Int(strip)) pt below the top (menu bar \(Int(menuBar)) pt uncovered)")
            check(p.sharingType != .none, "panel is capturable by screen sharing")
        }
        // Screen-parameter notification with an unchanged screen set: panels and annotations are kept.
        let layersBefore = canvas.layerCount
        screensChanged()
        check(canvas.window != nil && canvas.layerCount == layersBefore && panelUnderMouse()?.canvas === canvas,
              "unchanged screen set keeps the panels and their \(layersBefore) layer(s)")
        // Real display change while drawing AND typing: label committed, then panels rebuilt, hotkeys intact.
        selectTool(.text)
        canvas.mouseDown(with: ev(.leftMouseDown, CGPoint(x: cx, y: cy)))
        canvas.insertText("Rebuild", replacementRange: NSRange(location: NSNotFound, length: 0))
        let editingBeforeRebuild = isEditingText && modeHotKeyCount == 0
        screensChanged(force: true)
        check(editingBeforeRebuild && !isEditingText && isDrawing && modeHotKeyCount == n,
              "display change while typing ends the entry and restores the \(n) hotkeys")
        let oldPanelDropped = !panels.contains { $0.canvas === canvas }
        check(isDrawing && modeHotKeyCount == n && panelCount == NSScreen.screens.count && oldPanelDropped,
              "screen rebuild while drawing keeps drawing mode (\(isDrawing)), \(modeHotKeyCount)/\(n) keys, \(panelCount) panel(s), old panel dropped (\(oldPanelDropped))")
        setDrawing(false)
        check(!isDrawing && modeHotKeyCount == 0, "exit after a screen rebuild releases every drawing-mode key")
        check(frontRestored(), "focus restored after the display change")
        // Termination while drawing and typing: nothing left registered, focus handed back.
        setDrawing(true)
        if let c = panelUnderMouse()?.canvas {
            beginTextEntry(on: c, at: CGPoint(x: c.bounds.midX, y: c.bounds.midY))
            c.insertText("Quit", replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        let editingBeforeQuit = isEditingText && modeHotKeyCount == 0
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        check(!isDrawing && modeHotKeyCount == 0 && appDelegate.globalHotKeyCount == 0,
              "applicationWillTerminate releases drawing-mode and global hotkeys")
        check(editingBeforeQuit && !isEditingText && frontRestored(), "termination mid-entry ends it and restores focus")
        runLaserChecks(check, spin)
        runUndoClearChecks(check)
        NSLog("DemoInk selftest: keyboard state machine %@", ok ? "PASS" : "FAIL")
    }

    /// Laser (L): own colour (red by default), draws nothing, loop + blank cursor only while active, trail fades,
    /// every exit path (tool change, Esc, ⌃§, display change, termination) stops the loop and restores the cursor.
    private func runLaserChecks(_ check: (Bool, String) -> Void, _ spin: (Double) -> Void) {
        setDrawing(true)
        guard let canvas = panelUnderMouse()?.canvas, let window = canvas.window else { check(false, "laser: no panel"); return }
        laser.followsSystemMouse = false // synthetic events only: the real mouse must not interfere
        defer { laser.followsSystemMouse = true }
        func ev(_ type: NSEvent.EventType, _ p: CGPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func overPanel() -> Bool { panels.contains { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } }
        func laserHiddenEverywhere() -> Bool { panels.allSatisfy { !$0.canvas.laserVisible && $0.canvas.laserTrailEmpty } }
        func stopped() -> Bool { !laser.isRunning && !laser.isLinkRunning && laserHiddenEverywhere() }
        let b = canvas.bounds, cx = b.midX, cy = b.midY

        let reg = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)["laserColorIndex"] as? Int
        check(reg == 0 && palette[Settings.defaultLaserColorIndex].name == "Rouge", "laser colour defaults to red (registered default \(reg ?? -1))")
        let lKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                    characters: "l", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37)!
        let lShift = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
                                      context: nil, characters: "L", charactersIgnoringModifiers: "L", isARepeat: false, keyCode: 37)!
        check(OverlayController.action(for: lKey) == .tool(.laser) && OverlayController.action(for: lShift) == .tool(.laser)
              && modeKeyFailures.isEmpty, "L and ⇧L map to Laser, all drawing-mode keys registered")

        selectTool(.arrow)
        check(!laser.isRunning && !laser.isLinkRunning, "no laser loop while drawing with another tool")
        check(perform(.tool(.laser), source: "selftest") && Settings.shared.tool == .laser && laser.isRunning && laser.isLinkRunning,
              "L selects Laser and starts the animation loop")
        let expected = overPanel() ? LaserPointer.blankCursor : NSCursor.arrow
        check(drawingCursor === LaserPointer.blankCursor && NSCursor.current === expected,
              "cursor is blank over the panels while Laser (mouse over a panel: \(overPanel()))")

        // Colours: the laser has its own.
        let drawColor = Settings.shared.colorIndex
        let lc = drawColor == 3 ? 2 : 3
        perform(.color(lc), source: "selftest")
        check(Settings.shared.laserColorIndex == lc && Settings.shared.colorIndex == drawColor && Settings.shared.activeColorIndex == lc,
              "1–5 with Laser change the laser colour (\(lc)), not the drawing colour (\(drawColor))")
        selectColor(4) // ⌃⌥5 and the menu go through selectColor too
        check(Settings.shared.laserColorIndex == 4 && Settings.shared.colorIndex == drawColor, "⌃⌥5 with Laser changes the laser colour only")

        // A drag draws nothing; ⌘-drag still draws a temporary rectangle.
        let h0 = canvas.historyCount, l0 = canvas.layerCount
        canvas.mouseDown(with: ev(.leftMouseDown, CGPoint(x: cx - 200, y: cy)))
        for i in 1...20 { canvas.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: cx - 200 + CGFloat(i) * 15, y: cy + CGFloat(i) * 5))) }
        canvas.mouseUp(with: ev(.leftMouseUp, CGPoint(x: cx + 100, y: cy + 100)))
        check(canvas.historyCount == h0 && canvas.layerCount == l0, "a drag with Laser adds no layer and no undo entry")
        canvas.mouseDown(with: ev(.leftMouseDown, CGPoint(x: cx - 100, y: cy - 100), [.command]))
        canvas.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: cx + 50, y: cy - 20), [.command]))
        canvas.mouseUp(with: ev(.leftMouseUp, CGPoint(x: cx + 50, y: cy - 20), [.command]))
        check(canvas.historyCount == h0 + 1 && canvas.layerCount == l0 + 1 && Settings.shared.tool == .laser,
              "⌘-drag from Laser draws a rectangle (tool stays Laser)")
        canvas.undo()

        // Trail: present mid-motion, gone ~1 s after the motion stops; the dot follows the last position.
        var lastP = CGPoint.zero
        for i in 0..<30 {
            lastP = CGPoint(x: cx - 300 + CGFloat(i) * 20, y: cy + sin(CGFloat(i) / 4) * 80)
            canvas.mouseMoved(with: ev(.mouseMoved, lastP))
            spin(1.0 / 60)
        }
        let mid = laser.trailSampleCount, midPath = !canvas.laserTrailEmpty
        let dp = canvas.laserDotPosition
        check(mid > 3 && midPath && canvas.laserVisible && hypot(dp.x - lastP.x, dp.y - lastP.y) < 0.5,
              "mid-motion: dot at the mouse, trail of \(mid) samples drawn")
        spin(1.0)
        check(laser.trailIsEmpty && canvas.laserTrailEmpty && canvas.laserVisible, "1 s after the motion stops the trail is empty, the dot remains")
        let ticks0 = laser.tickCount
        spin(0.3)
        check(laser.tickCount > ticks0, "loop ticking while Laser is active (\(laser.tickCount - ticks0) frames in 0.3 s)")
        if let other = panels.first(where: { $0.canvas !== canvas }) {
            laser.moved(to: CGPoint(x: other.frame.midX, y: other.frame.midY))
            spin(0.1)
            check(other.canvas.laserVisible && !canvas.laserVisible && canvas.laserTrailEmpty,
                  "moving to another screen: dot there, nothing left on the first screen")
            laser.moved(to: window.convertPoint(toScreen: lastP))
            spin(0.1)
        }

        // Exit paths.
        check(perform(.tool(.pen), source: "selftest") && stopped() && NSCursor.current === NSCursor.crosshair,
              "leaving Laser (P) stops the loop, hides the dot, crosshair back")
        perform(.color(2), source: "selftest")
        check(Settings.shared.colorIndex == 2 && Settings.shared.laserColorIndex == 4, "outside Laser, 1–5 change the drawing colour only")
        perform(.tool(.laser), source: "selftest")
        check(laser.isRunning && Settings.shared.activeColorIndex == 4, "back to Laser: loop restarted, laser colour kept")
        perform(.exit, source: "selftest")
        check(!isDrawing && stopped() && NSCursor.current === NSCursor.arrow, "Esc stops the laser loop and restores the arrow")
        check(Settings.shared.tool == .laser && !laser.isRunning, "Laser selected but drawing mode off: no loop")
        setDrawing(true)
        check(laser.isRunning, "drawing mode on with Laser: loop running")
        toggle()
        check(!isDrawing && stopped() && NSCursor.current === NSCursor.arrow, "⌃§ stops the laser loop and restores the arrow")
        setDrawing(true)
        screensChanged(force: true)
        check(isDrawing && laser.isRunning && laser.isLinkRunning && panelCount == NSScreen.screens.count
              && drawingCursor === LaserPointer.blankCursor, "display change: panels rebuilt, laser restarted on them")
        terminate()
        check(!isDrawing && stopped() && modeHotKeyCount == 0 && NSCursor.current === NSCursor.arrow,
              "termination stops the laser loop and restores the arrow")
        setDrawing(true)
        selectTool(.arrow)
        setDrawing(false)
        check(stopped(), "laser idle at the end")
    }

    /// ⌘Z undoes stroke by stroke back to an empty screen, then is a no-op; E (clear all) stays in drawing mode and
    /// keeps the current tool.
    private func runUndoClearChecks(_ check: (Bool, String) -> Void) {
        setDrawing(true)
        guard let canvas = panelUnderMouse()?.canvas, let window = canvas.window else { check(false, "undo/clear: no panel"); return }
        func ev(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let prevTool = Settings.shared.tool
        let b = canvas.bounds, p = CGPoint(x: b.midX, y: b.midY)
        selectTool(.pen)
        canvas.mouseDown(with: ev(.leftMouseDown, p))
        canvas.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: p.x - 60, y: p.y + 60)))
        canvas.mouseUp(with: ev(.leftMouseUp, CGPoint(x: p.x - 60, y: p.y + 60)))
        let h0 = canvas.historyCount
        perform(.clearAll, source: "selftest")
        check(h0 > 0 && isDrawing && Settings.shared.tool == .pen && canvas.historyCount == 0,
              "E clears everything, stays in drawing mode, keeps the tool")
        for i in 0..<3 {
            canvas.mouseDown(with: ev(.leftMouseDown, CGPoint(x: p.x, y: p.y + CGFloat(i) * 30)))
            canvas.mouseDragged(with: ev(.leftMouseDragged, CGPoint(x: p.x + 90, y: p.y + CGFloat(i) * 30)))
            canvas.mouseUp(with: ev(.leftMouseUp, CGPoint(x: p.x + 90, y: p.y + CGFloat(i) * 30)))
        }
        let drawn = canvas.historyCount
        perform(.undo, source: "selftest")
        let afterOne = canvas.historyCount
        for _ in 0..<3 { canvas.undo() } // same call as ⌘Z (a repeated perform within 50 ms would be deduplicated)
        check(drawn == 3 && afterOne == 2 && canvas.historyCount == 0 && isDrawing,
              "⌘Z undoes back to empty, then is a no-op")
        selectTool(prevTool)
        setDrawing(false)
    }

    /// DEMOINK_SELFTEST=laser: Laser in drawing mode, the dot moved along a figure-eight by synthetic mouseMoved
    /// events (120 Hz), pausing 1 s every 4 s so the tail can be seen retracting. Runs DEMOINK_LASER_SECONDS
    /// (default 20), then restores tool + laser colour and leaves drawing mode. DEMOINK_BOARD=white|black adds a board,
    /// DEMOINK_LASER_COLOR=1…5 picks the laser colour.
    func runLaserDemo(on canvas: CanvasView) {
        guard let window = canvas.window else { return }
        let env = ProcessInfo.processInfo.environment
        let saved = (Settings.shared.tool, Settings.shared.laserColorIndex)
        setDrawing(true)
        switch env["DEMOINK_BOARD"] {
        case "white": setBoard(.white)
        case "black": setBoard(.black)
        default: break
        }
        selectTool(.laser)
        if let s = env["DEMOINK_LASER_COLOR"], let i = Int(s), (1...5).contains(i) { selectColor(i - 1) }
        laser.followsSystemMouse = false
        let seconds = Double(env["DEMOINK_LASER_SECONDS"] ?? "") ?? 20
        let b = canvas.bounds, cx = b.midX, cy = b.midY
        let t0 = CACurrentMediaTime()
        var motionTime: Double = 0, lastT = t0
        NSLog("DemoInk laser demo: %.0f s on canvas %.0fx%.0f, colour %@", seconds, b.width, b.height, Settings.shared.laserColor.name)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            let now = CACurrentMediaTime()
            let e = now - t0
            if e > seconds {
                t.invalidate()
                self.laser.followsSystemMouse = true
                Settings.shared.laserColorIndex = saved.1
                self.selectTool(saved.0)
                self.setDrawing(false)
                NSLog("DemoInk laser demo: done (laser running: %d)", self.laser.isRunning ? 1 : 0)
                return
            }
            let paused = e.truncatingRemainder(dividingBy: 4) > 3
            if !paused { motionTime += now - lastT }
            lastT = now
            if paused { return }
            let p = CGPoint(x: cx + 480 * sin(motionTime * 1.3), y: cy + 220 * sin(motionTime * 2.6))
            canvas.mouseMoved(with: NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [],
                                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                       clickCount: 0, pressure: 0)!)
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// DEMOINK_SELFTEST=text: labels in several colours and sizes (multi-line, one at the bottom-right edge) plus a
    /// label still being typed (caret visible), left on screen for `screencapture`. DEMOINK_BOARD=white|black adds a board.
    func runTextGallery(on canvas: CanvasView) {
        guard let window = canvas.window else { return }
        let saved = (Settings.shared.tool, Settings.shared.colorIndex, Settings.shared.width)
        setDrawing(true)
        switch ProcessInfo.processInfo.environment["DEMOINK_BOARD"] {
        case "white": setBoard(.white)
        case "black": setBoard(.black)
        default: break
        }
        func click(_ p: CGPoint) {
            canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0,
                                                      windowNumber: window.windowNumber, context: nil,
                                                      eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        func label(_ s: String, _ p: CGPoint, color: Int, width: CGFloat, commit: Bool = true) {
            selectTool(.text); selectColor(color); Settings.shared.width = width
            click(p)
            canvas.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0))
            if commit { endTextEntry(commit: true) }
        }
        let b = canvas.bounds
        let cx = b.midX, cy = b.midY
        label("Small red 2", CGPoint(x: cx - 600, y: cy + 250), color: 0, width: 2)
        label("Default 28 pt (width 8)", CGPoint(x: cx - 600, y: cy + 150), color: 4, width: 8)
        label("Big green 20", CGPoint(x: cx - 600, y: cy + 20), color: 3, width: 20)
        label("Multi-line label\nsecond line, yellow\nthird", CGPoint(x: cx + 100, y: cy + 250), color: 2, width: 6)
        label("Clamped at the bottom-right edge\nstays on screen", CGPoint(x: b.maxX - 4, y: b.minY + 4), color: 1, width: 10)
        label("Typing in progress", CGPoint(x: cx - 600, y: cy - 200), color: 4, width: 10, commit: false)
        Settings.shared.tool = saved.0; Settings.shared.colorIndex = saved.1; Settings.shared.width = saved.2
        onStateChange?()
        NSLog("DemoInk text gallery: %d layers, %d labels committed, editing: %d", canvas.layerCount, canvas.textCount,
              isEditingText ? 1 : 0)
    }

    /// DEMOINK_SELFTEST=shapes: ovals/circles and Count markers 1…12 (incl. every edge and corner), left on screen
    /// for `screencapture`. Each marker's click point is logged so the tail tip can be checked in the capture.
    func runShapesGallery(on canvas: CanvasView) {
        guard let window = canvas.window else { return }
        let saved = (Settings.shared.tool, Settings.shared.colorIndex, Settings.shared.width, Settings.shared.clearOnExit)
        setDrawing(true)
        func ev(_ type: NSEvent.EventType, _ p: CGPoint, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func drag(_ t: Tool, _ s: CGPoint, _ e: CGPoint, _ flags: NSEvent.ModifierFlags = []) {
            selectTool(t)
            canvas.mouseDown(with: ev(.leftMouseDown, s, flags))
            canvas.mouseDragged(with: ev(.leftMouseDragged, e, flags))
            canvas.mouseUp(with: ev(.leftMouseUp, e, flags))
        }
        let b = canvas.bounds
        let cx = b.midX, cy = b.midY
        for (i, w) in ([2, 4, 10] as [CGFloat]).enumerated() {
            Settings.shared.width = w
            selectColor(i)
            let x = cx - 500 + CGFloat(i) * 230
            drag(.oval, CGPoint(x: x, y: cy + 120), CGPoint(x: x + 200, y: cy + 230))
            drag(.oval, CGPoint(x: x, y: cy - 60), CGPoint(x: x + 200, y: cy + 60), [.shift]) // circle
        }
        Settings.shared.width = 4
        let spots: [CGPoint] = [
            CGPoint(x: cx + 250, y: cy - 150), CGPoint(x: cx + 330, y: cy - 150), CGPoint(x: cx + 410, y: cy - 150),
            CGPoint(x: b.minX + 4, y: cy), CGPoint(x: b.maxX - 4, y: cy),
            CGPoint(x: cx, y: b.maxY - 4), CGPoint(x: cx, y: b.minY + 4),
            CGPoint(x: b.maxX - 4, y: b.maxY - 4), CGPoint(x: b.minX + 4, y: b.minY + 4),
            CGPoint(x: b.minX + 4, y: b.maxY - 4), CGPoint(x: b.maxX - 4, y: b.minY + 4),
            CGPoint(x: cx + 490, y: cy - 150),
        ]
        selectTool(.counter)
        for (i, p) in spots.enumerated() {
            selectColor(i % palette.count)
            canvas.mouseDown(with: ev(.leftMouseDown, p))
            canvas.mouseUp(with: ev(.leftMouseUp, p))
            NSLog("DemoInk shapes gallery: marker %d tip at (%.1f, %.1f) [canvas %.0fx%.0f, y up]", i + 1, p.x, p.y, b.width, b.height)
        }
        // Width scaling: markers at 1, 8 and 24 pt (numbers 13…15).
        for (i, w) in ([1, 8, 24] as [CGFloat]).enumerated() {
            Settings.shared.width = w
            let p = CGPoint(x: cx + 250 + CGFloat(i) * 110, y: cy - 330)
            canvas.mouseDown(with: ev(.leftMouseDown, p))
            canvas.mouseUp(with: ev(.leftMouseUp, p))
            NSLog("DemoInk shapes gallery: marker %d (width %.0f) tip at (%.1f, %.1f)", 13 + i, w, p.x, p.y)
        }
        Settings.shared.tool = saved.0; Settings.shared.colorIndex = saved.1; Settings.shared.width = saved.2
        Settings.shared.clearOnExit = saved.3
        onStateChange?()
        NSLog("DemoInk shapes gallery: %d layers drawn, next marker %d", canvas.layerCount, nextMarkerNumber())
    }
}
