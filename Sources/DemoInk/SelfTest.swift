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
        let saved = (Settings.shared.tool, Settings.shared.colorIndex, Settings.shared.width, Settings.shared.clearOnExit)
        defer { Settings.shared.tool = saved.0; Settings.shared.colorIndex = saved.1; Settings.shared.width = saved.2
                Settings.shared.clearOnExit = saved.3
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
        // Real display change while drawing: panels rebuilt, drawing mode / hotkeys / one panel per screen intact.
        screensChanged(force: true)
        let oldPanelDropped = !panels.contains { $0.canvas === canvas }
        check(isDrawing && modeHotKeyCount == n && panelCount == NSScreen.screens.count && oldPanelDropped,
              "screen rebuild while drawing keeps drawing mode (\(isDrawing)), \(modeHotKeyCount)/\(n) keys, \(panelCount) panel(s), old panel dropped (\(oldPanelDropped))")
        setDrawing(false)
        check(!isDrawing && modeHotKeyCount == 0, "exit after a screen rebuild releases every drawing-mode key")
        // Termination while drawing: nothing left registered.
        setDrawing(true)
        appDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        check(!isDrawing && modeHotKeyCount == 0 && appDelegate.globalHotKeyCount == 0,
              "applicationWillTerminate releases drawing-mode and global hotkeys")
        NSLog("DemoInk selftest: keyboard state machine %@", ok ? "PASS" : "FAIL")
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
