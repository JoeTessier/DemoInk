import AppKit
import QuartzCore

/// Layer-hosting view covering one screen. Each annotation is its own CAShapeLayer;
/// live preview only replaces the current layer's path.
final class CanvasView: NSView {
    weak var controller: OverlayController?
    private let scale: CGFloat

    private let boardLayer = CALayer()
    private let spotlightContainer = CALayer()
    private let shapesContainer = CALayer()
    private let hud = HUDLayer()

    private enum Entry { case shape(CAShapeLayer), spotlight(CAShapeLayer), marker(CAShapeLayer, Int) }
    private var history: [Entry] = []

    // Current gesture
    private var current: CAShapeLayer?
    private var baseTool: Tool = .arrow
    private var activeTool: Tool = .arrow
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var points: [CGPoint] = []
    private var flags: NSEvent.ModifierFlags = []
    private var scrollAccumulator: CGFloat = 0
    private var markerNumber = 0            // number of the in-progress Count marker

    /// Highest Count-marker number on this screen (0 if none).
    var maxMarkerNumber: Int {
        history.reduce(0) { m, e in if case .marker(_, let n) = e { return max(m, n) }; return m }
    }
    var markerCount: Int { history.reduce(0) { m, e in if case .marker = e { return m + 1 }; return m } }

    var hasContent: Bool { !history.isEmpty || current != nil || !boardLayer.isHidden }

    init(frame: NSRect, scale: CGFloat) {
        self.scale = scale
        super.init(frame: frame)
        let root = CALayer()
        root.contentsScale = scale
        layer = root
        wantsLayer = true
        for l in [boardLayer, spotlightContainer, shapesContainer] {
            l.frame = bounds
            l.contentsScale = scale
            root.addSublayer(l)
        }
        boardLayer.isHidden = true
        hud.contentsScale = scale
        root.addSublayer(hud)
        root.actions = ["sublayers": NSNull()]
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved,
                                                               .mouseEnteredAndExited, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    private func updateCursor() { if controller?.isDrawing == true { NSCursor.crosshair.set() } }
    override func cursorUpdate(with event: NSEvent) { updateCursor() }
    override func mouseMoved(with event: NSEvent) { updateCursor() }
    override func mouseEntered(with event: NSEvent) { updateCursor() }
    override func resetCursorRects() {
        if controller?.isDrawing == true { addCursorRect(bounds, cursor: .crosshair) }
    }

    // MARK: Keys — fallback path only. Drawing-mode keys are Carbon hotkeys (see OverlayController);
    // these fire only if the panel somehow has keyboard focus, and go through the same deduplicated handler.

    override func keyDown(with event: NSEvent) { _ = controller?.handleKey(event) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard controller?.isDrawing == true else { return false }
        return controller?.handleKey(event) ?? false
    }
    override func cancelOperation(_ sender: Any?) { controller?.perform(.exit, source: "panel-cancel") }

    override func flagsChanged(with event: NSEvent) {
        flags = event.modifierFlags
        if current != nil { updatePreview() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard controller?.isDrawing == true else { return }
        let dy = event.scrollingDeltaY
        scrollAccumulator += event.hasPreciseScrollingDeltas ? dy / 8 : dy
        let steps = Int(scrollAccumulator.rounded(.towardZero))
        if steps != 0 {
            scrollAccumulator -= CGFloat(steps)
            controller?.changeWidth(by: CGFloat(steps))
        }
    }

    // MARK: Drawing

    private static func effectiveTool(base: Tool, flags: NSEvent.ModifierFlags) -> Tool {
        guard [.arrow, .rectangle, .oval, .pen, .counter].contains(base) else { return base }
        if flags.contains(.command) { return .rectangle }
        if flags.contains(.option) { return .arrow }
        return base
    }

    override func mouseDown(with event: NSEvent) {
        guard controller?.isDrawing == true else { return }
        window?.makeKey()
        NSCursor.crosshair.set()
        let p = convert(event.locationInWindow, from: nil)
        start = p; last = p; points = [p]
        flags = event.modifierFlags
        baseTool = Settings.shared.tool
        activeTool = CanvasView.effectiveTool(base: baseTool, flags: flags)
        if activeTool == .counter { markerNumber = controller?.nextMarkerNumber() ?? 1 }

        let l = CAShapeLayer()
        l.contentsScale = scale
        l.frame = bounds
        l.actions = ["path": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(),
                     "hidden": NSNull(), "opacity": NSNull()]
        current = l
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if activeTool == .spotlight {
            visibleSpotlight()?.isHidden = true
            spotlightContainer.addSublayer(l)
        } else {
            shapesContainer.addSublayer(l)
        }
        applyStyle()
        updatePreview()
        CATransaction.commit()
    }

    override func mouseDragged(with event: NSEvent) {
        guard current != nil else { return }
        let p = convert(event.locationInWindow, from: nil)
        flags = event.modifierFlags
        last = p
        if let lp = points.last, hypot(p.x - lp.x, p.y - lp.y) >= 1.5 { points.append(p) }
        updatePreview()
    }

    override func mouseUp(with event: NSEvent) {
        guard let l = current else { return }
        last = convert(event.locationInWindow, from: nil)
        if let lp = points.last, lp != last { points.append(last) }
        updatePreview()
        current = nil
        let size = hypot(last.x - start.x, last.y - start.y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if activeTool == .spotlight {
            let r = Geometry.rect(from: start, to: last, square: flags.contains(.shift))
            if r.width < 4 || r.height < 4 {
                l.removeFromSuperlayer()
                visibleSpotlight()?.isHidden = false
            } else {
                history.append(.spotlight(l))
            }
        } else if activeTool == .counter {
            history.append(.marker(l, markerNumber)) // a plain click is the whole gesture
        } else if l.path == nil || (activeTool != .pen && size < 3) {
            l.removeFromSuperlayer()
        } else {
            history.append(.shape(l))
        }
        CATransaction.commit()
        controller?.contentChanged()
    }

    /// Re-applies colour/width/tool style to the in-progress layer (also called mid-drag on colour change).
    func applyStyle() {
        guard let l = current else { return }
        let s = Settings.shared
        let color = s.color.color.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.shadowOpacity = 0
        l.lineDashPattern = nil
        switch activeTool {
        case .arrow:
            // One closed outline, non-zero fill. The hairline stroke (same opaque colour, same path)
            // only rounds the tip/wing corners; it never overlaps a different subpath.
            l.fillColor = color
            l.fillRule = .nonZero
            l.strokeColor = color
            l.lineWidth = 1
            l.lineJoin = .round
            l.lineCap = .round
            setShadow(l)
        case .rectangle, .oval, .pen:
            l.fillColor = nil
            l.strokeColor = color
            l.lineWidth = s.width
            l.lineCap = .round
            l.lineJoin = .round
            setShadow(l)
        case .highlighter:
            l.fillColor = nil
            l.strokeColor = s.color.color.withAlphaComponent(0.35).cgColor
            l.lineWidth = max(10, s.width * 4.5)
            l.lineCap = .butt
            l.lineJoin = .round
        case .spotlight:
            l.fillColor = NSColor.black.withAlphaComponent(0.6).cgColor
            l.strokeColor = nil
            l.fillRule = .evenOdd
        case .counter:
            // One bubble+tail outline, non-zero fill, thin white border; the number is a white glyph sublayer.
            l.fillColor = color
            l.fillRule = .nonZero
            l.strokeColor = NSColor.white.cgColor
            l.lineWidth = 2
            l.lineJoin = .round
            l.lineCap = .round
            setShadow(l)
        }
        if activeTool != .counter { l.sublayers?.forEach { $0.removeFromSuperlayer() } }
        CATransaction.commit()
    }

    private func setShadow(_ l: CALayer) {
        l.shadowColor = NSColor.black.cgColor
        l.shadowOpacity = 0.35
        l.shadowRadius = 3
        l.shadowOffset = CGSize(width: 0, height: -1)
    }

    private func updatePreview() {
        guard let l = current else { return }
        var newTool = CanvasView.effectiveTool(base: baseTool, flags: flags)
        // From Count, a gesture is either a marker (plain click) or a ⌘/⌥ override for its whole life:
        // modifiers pressed/released mid-drag only switch between rectangle and arrow.
        if baseTool == .counter, newTool == .counter || activeTool == .counter { newTool = activeTool }
        if newTool != activeTool { activeTool = newTool; applyStyle() }
        let shift = flags.contains(.shift)
        let w = Settings.shared.width
        let path: CGPath?
        switch activeTool {
        case .arrow:
            path = Geometry.arrowPath(from: start, to: shift ? Geometry.snap45(from: start, to: last) : last, width: w)
        case .rectangle:
            let r = Geometry.rect(from: start, to: last, square: shift)
            path = (r.width < 1 && r.height < 1) ? nil : Geometry.roundedRectPath(r, radius: 6)
        case .oval:
            let r = Geometry.rect(from: start, to: last, square: shift) // ⇧: circle
            path = (r.width < 1 && r.height < 1) ? nil : Geometry.ellipsePath(r)
        case .counter:
            let d = Geometry.markerDiameter(width: w)
            let bubble = Geometry.markerBubble(tip: last, diameter: d, in: markerArea)
            path = bubble.path
            let label: CAShapeLayer
            if let existing = l.sublayers?.first as? CAShapeLayer {
                label = existing
            } else {
                label = CAShapeLayer()
                label.contentsScale = scale
                label.frame = bounds
                label.actions = ["path": NSNull(), "fillColor": NSNull()]
                label.fillColor = NSColor.white.cgColor
                label.strokeColor = nil
                l.addSublayer(label)
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            label.path = Geometry.markerNumberPath(markerNumber, center: bubble.center, diameter: d)
            CATransaction.commit()
        case .highlighter:
            if shift {
                let p = CGMutablePath()
                p.move(to: start)
                p.addLine(to: CGPoint(x: last.x, y: start.y))
                path = p
            } else {
                path = Geometry.smoothPath(points)
            }
        case .pen:
            path = Geometry.smoothPath(points)
        case .spotlight:
            let p = CGMutablePath()
            p.addRect(bounds)
            let r = Geometry.rect(from: start, to: last, square: shift)
            if r.width >= 1 && r.height >= 1 { p.addPath(Geometry.roundedRectPath(r, radius: 12)) }
            path = p
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.path = path
        CATransaction.commit()
    }

    /// Where a Count bubble may sit: the whole canvas (the panel already stops below the menu-bar strip).
    private var markerArea: CGRect { bounds }

    func refreshCurrent() {
        applyStyle()
        updatePreview()
    }

    /// Drops the in-progress gesture without committing it (Esc pressed mid-drag). The later mouseUp is a no-op.
    func cancelCurrent() {
        guard let l = current else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.removeFromSuperlayer()
        if activeTool == .spotlight { visibleSpotlight()?.isHidden = false }
        CATransaction.commit()
        current = nil
    }

    /// Number of annotation layers currently on screen (shapes + spotlights + in-progress + board). Diagnostics.
    var layerCount: Int {
        (shapesContainer.sublayers?.count ?? 0) + (spotlightContainer.sublayers?.count ?? 0) + (boardLayer.isHidden ? 0 : 1)
    }

    private func visibleSpotlight() -> CAShapeLayer? {
        for e in history.reversed() { if case .spotlight(let l) = e { return l } }
        return nil
    }

    // MARK: Undo / clear / boards

    func undo() {
        guard let e = history.popLast() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch e {
        case .shape(let l), .marker(let l, _): l.removeFromSuperlayer()
        case .spotlight(let l):
            l.removeFromSuperlayer()
            visibleSpotlight()?.isHidden = false
        }
        CATransaction.commit()
    }

    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current?.removeFromSuperlayer()
        current = nil
        for e in history {
            switch e { case .shape(let l), .spotlight(let l), .marker(let l, _): l.removeFromSuperlayer() }
        }
        history.removeAll()
        boardLayer.isHidden = true
        CATransaction.commit()
    }

    func setBoard(_ color: NSColor?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let color = color {
            boardLayer.backgroundColor = color.cgColor
            boardLayer.isHidden = false
        } else {
            boardLayer.isHidden = true
        }
        CATransaction.commit()
    }

    func showHUD(_ text: String) { hud.show(text, in: bounds) }
}

/// Small rounded label at top-centre that fades out.
final class HUDLayer: CALayer {
    private let text = CATextLayer()
    private var hideWork: DispatchWorkItem?

    override init() {
        super.init()
        backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        cornerRadius = 10
        opacity = 0
        text.alignmentMode = .center
        text.foregroundColor = NSColor.white.cgColor
        text.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        text.fontSize = 15
        addSublayer(text)
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ string: String, in bounds: CGRect) {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let size = (string as NSString).size(withAttributes: [.font: font])
        let w = ceil(size.width) + 28, h = ceil(size.height) + 14
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        text.contentsScale = contentsScale
        text.string = string
        frame = CGRect(x: (bounds.width - w) / 2, y: bounds.height - h - 70, width: w, height: h)
        text.frame = CGRect(x: 0, y: (h - ceil(size.height)) / 2, width: w, height: ceil(size.height))
        removeAllAnimations()
        opacity = 1
        CATransaction.commit()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.3)
            self?.opacity = 0
            CATransaction.commit()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}
