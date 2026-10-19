import AppKit
import QuartzCore

// Laser pointer (L). Purely ephemeral: a glowing dot that replaces the cursor over the panels, plus a short tail
// that fades out ~0.4 s after the motion that drew it. Nothing is ever added to a canvas's history.
// Mouse positions arrive from the panels' mouseMoved / mouseDragged (screen coordinates); rendering happens on a
// display link (CADisplayLink on macOS 14+, a 60 Hz timer on macOS 13) that exists ONLY while Laser is the tool in
// drawing mode, so there is no idle cost otherwise. The dot is drawn only on the panel under it.

final class LaserPointer: NSObject {
    static let coreDiameter: CGFloat = 11
    static let haloDiameter: CGFloat = 46
    static let trailDuration: CFTimeInterval = 0.4

    /// Transparent cursor used over the panels while the laser is active (set through the normal cursor-rect /
    /// cursorUpdate mechanism, so no NSCursor.hide/unhide count to balance).
    static let blankCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        return NSCursor(image: img, hotSpot: NSPoint(x: 8, y: 8))
    }()

    weak var controller: OverlayController?
    private(set) var isRunning = false
    /// Also follow NSEvent.mouseLocation when no mouse event arrived for 50 ms (safety net). Off in synthetic tests.
    var followsSystemMouse = true
    private var samples: [(p: CGPoint, t: CFTimeInterval)] = []   // screen coordinates, oldest first
    private var lastEventTime: CFTimeInterval = 0
    private weak var activePanel: OverlayPanel?
    private var link: AnyObject?                                    // CADisplayLink or Timer
    private var linkScreen: NSScreen?
    private var idleRendered = false
    private(set) var tickCount = 0

    /// True when no tail is left (only the dot's own position, or nothing).
    var trailIsEmpty: Bool { samples.count <= 1 }
    var trailSampleCount: Int { max(0, samples.count - 1) }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let now = CACurrentMediaTime()
        samples = [(NSEvent.mouseLocation, now)]
        lastEventTime = 0
        idleRendered = false
        activePanel = nil
        render(now)
        if link == nil { startLink(on: activePanel?.targetScreen ?? controller?.panelUnderMouse()?.targetScreen) }
        NSLog("DemoInk: laser ON")
    }

    func stop() {
        stopLink()
        controller?.panels.forEach { $0.canvas.hideLaser() }
        samples = []
        activePanel = nil
        guard isRunning else { return }
        isRunning = false
        NSLog("DemoInk: laser OFF (%d frames)", tickCount)
    }

    /// Mouse moved / dragged over a panel (screen coordinates).
    func moved(to p: CGPoint) {
        guard isRunning else { return }
        let now = CACurrentMediaTime()
        lastEventTime = now
        if let last = samples.last, last.p == p { return }
        samples.append((p, now))
        idleRendered = false
    }

    /// Laser colour changed: redraw at once (the dot may be still).
    func refresh() {
        guard isRunning else { return }
        idleRendered = false
        render(CACurrentMediaTime())
    }

    // MARK: Animation loop

    private func startLink(on screen: NSScreen?) {
        stopLink()
        if #available(macOS 14.0, *), let screen = screen {
            let l = screen.displayLink(target: self, selector: #selector(tick))
            // The screen's full refresh rate (ProMotion would otherwise be allowed to drop it).
            let maxFPS = Float(max(1, screen.maximumFramesPerSecond))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maxFPS), maximum: maxFPS, preferred: maxFPS)
            l.add(to: .main, forMode: .common)
            link = l
            linkScreen = screen
        } else {
            let t = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            link = t
            linkScreen = nil
        }
    }

    private func stopLink() {
        if #available(macOS 14.0, *), let l = link as? CADisplayLink { l.invalidate() }
        (link as? Timer)?.invalidate()
        link = nil
        linkScreen = nil
    }

    var isLinkRunning: Bool { link != nil }

    @objc private func tick() {
        guard isRunning else { stopLink(); return }
        tickCount += 1
        let now = CACurrentMediaTime()
        if followsSystemMouse, now - lastEventTime > 0.05 {
            let m = NSEvent.mouseLocation
            if let last = samples.last, hypot(m.x - last.p.x, m.y - last.p.y) > 0.5 {
                samples.append((m, now))
                idleRendered = false
            }
        }
        // Expire the tail; the newest sample (the dot) always stays.
        if samples.count > 1 {
            let keepFrom = samples.firstIndex { now - $0.t <= LaserPointer.trailDuration } ?? samples.count - 1
            if keepFrom > 0 { samples.removeFirst(min(keepFrom, samples.count - 1)) }
        }
        if samples.count <= 1 && idleRendered { return } // still dot already drawn: nothing to do this frame
        render(now)
        idleRendered = samples.count <= 1
    }

    private func render(_ now: CFTimeInterval) {
        guard let controller = controller, let head = samples.last?.p else { return }
        let panel = controller.panels.first { NSMouseInRect(head, $0.frame, false) }
        if panel !== activePanel {
            activePanel?.canvas.hideLaser()   // nothing left behind on the screen the dot just left
            activePanel = panel
            if let panel = panel, link != nil, #available(macOS 14.0, *), linkScreen != panel.targetScreen {
                startLink(on: panel.targetScreen) // follow that screen's refresh rate
            }
        }
        guard let panel = panel else { return } // over the menu bar: the system cursor shows, no dot
        let o = panel.frame.origin
        var pts: [CGPoint] = [], half: [CGFloat] = []
        for s in samples {
            pts.append(CGPoint(x: s.p.x - o.x, y: s.p.y - o.y))
            let f = max(0, 1 - CGFloat((now - s.t) / LaserPointer.trailDuration))
            half.append(LaserPointer.coreDiameter * 0.45 * f)
        }
        panel.canvas.renderLaser(head: pts[pts.count - 1], trail: Geometry.taperedTrail(pts, halfWidths: half),
                                 glow: Geometry.taperedTrail(pts, halfWidths: half.map { $0 * 2.3 }),
                                 color: Settings.shared.laserColor.color)
    }

    // MARK: Dot image (solid core + soft halo), cached per colour and scale

    private static var dotCache: [String: CGImage] = [:]

    static func dotImage(color: NSColor, scale: CGFloat) -> CGImage? {
        let c = color.usingColorSpace(.sRGB) ?? color
        let key = String(format: "%.3f-%.3f-%.3f-%.1f", c.redComponent, c.greenComponent, c.blueComponent, scale)
        if let img = dotCache[key] { return img }
        let px = Int((haloDiameter * scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let center = CGPoint(x: haloDiameter / 2, y: haloDiameter / 2)
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        func col(_ a: CGFloat) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
        // Halo: smooth falloff from the core edge to the image edge.
        let coreR = coreDiameter / 2, haloR = haloDiameter / 2
        let k = coreR / haloR
        let stops: [(CGFloat, CGFloat)] = [(0, 0.65), (k, 0.6), (k + (1 - k) * 0.2, 0.32), (k + (1 - k) * 0.45, 0.13),
                                           (k + (1 - k) * 0.7, 0.04), (1, 0)]
        if let grad = CGGradient(colorsSpace: space, colors: stops.map { col($0.1) } as CFArray,
                                 locations: stops.map { $0.0 }) {
            ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: haloR, options: [])
        }
        // Solid core.
        ctx.setFillColor(col(1))
        ctx.fillEllipse(in: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreDiameter, height: coreDiameter))
        // Hot centre: a little white highlight so the dot reads as light, not as a sticker.
        if let hot = CGGradient(colorsSpace: space,
                                colors: [CGColor(colorSpace: space, components: [1, 1, 1, 0.75])!,
                                         CGColor(colorSpace: space, components: [1, 1, 1, 0])!] as CFArray,
                                locations: [0, 1]) {
            ctx.drawRadialGradient(hot, startCenter: center, startRadius: 0, endCenter: center, endRadius: coreR * 0.7, options: [])
        }
        guard let img = ctx.makeImage() else { return nil }
        dotCache[key] = img
        return img
    }
}

extension Geometry {
    /// Tail as ONE closed outline (non-zero fill): left edge from the oldest point to the newest, a round cap at the
    /// newest point, right edge back. `halfWidths` taper to 0 at the old end. Nil when there is no tail.
    static func taperedTrail(_ pts: [CGPoint], halfWidths: [CGFloat]) -> CGPath? {
        var P: [CGPoint] = [], H: [CGFloat] = []
        for (p, h) in zip(pts, halfWidths) {
            if let l = P.last, hypot(p.x - l.x, p.y - l.y) < 0.5 { P[P.count - 1] = p; H[H.count - 1] = h; continue }
            P.append(p); H.append(h)
        }
        let n = P.count
        guard n >= 2, (H.max() ?? 0) > 0.05 else { return nil }
        var left: [CGPoint] = [], right: [CGPoint] = []
        var lastNormal = CGPoint(x: 0, y: 1)
        for i in 0..<n {
            let a = P[max(i - 1, 0)], b = P[min(i + 1, n - 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            if len > 0.001 { lastNormal = CGPoint(x: -dy / len, y: dx / len) }
            left.append(CGPoint(x: P[i].x + lastNormal.x * H[i], y: P[i].y + lastNormal.y * H[i]))
            right.append(CGPoint(x: P[i].x - lastNormal.x * H[i], y: P[i].y - lastNormal.y * H[i]))
        }
        let path = CGMutablePath()
        path.move(to: left[0])
        for p in left.dropFirst() { path.addLine(to: p) }
        let ang = atan2(lastNormal.y, lastNormal.x)
        if H[n - 1] > 0.05 {
            path.addArc(center: P[n - 1], radius: H[n - 1], startAngle: ang, endAngle: ang - .pi, clockwise: true)
        }
        for p in right.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Canvas side

extension CanvasView {
    /// Draws the dot at `head`, the tail and its wider glow (nil = none) in `color`, without implicit animations.
    func renderLaser(head: CGPoint, trail: CGPath?, glow: CGPath?, color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        laserLayer.isHidden = false
        if laserDotColor != color {
            laserDotColor = color
            laserDot.contents = LaserPointer.dotImage(color: color, scale: scale)
            laserTrail.fillColor = color.withAlphaComponent(0.9).cgColor
            laserGlow.fillColor = color.withAlphaComponent(0.22).cgColor
        }
        laserDot.position = head
        laserTrail.path = trail
        laserGlow.path = glow
        CATransaction.commit()
    }

    func hideLaser() {
        guard !laserLayer.isHidden || laserTrail.path != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        laserLayer.isHidden = true
        laserTrail.path = nil
        laserGlow.path = nil
        CATransaction.commit()
    }

    var laserVisible: Bool { !laserLayer.isHidden }
    var laserTrailEmpty: Bool { laserTrail.path == nil }
    var laserDotPosition: CGPoint { laserDot.position }
}
