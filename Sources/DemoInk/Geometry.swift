import CoreGraphics
import CoreText
import Foundation

enum Geometry {
    static func snap45(from s: CGPoint, to e: CGPoint) -> CGPoint {
        let dx = e.x - s.x, dy = e.y - s.y
        let len = hypot(dx, dy)
        guard len > 0 else { return e }
        let step = CGFloat.pi / 4
        let a = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: s.x + cos(a) * len, y: s.y + sin(a) * len)
    }

    /// Arrow as ONE closed outline (no overlapping subpaths), meant for a non-zero fill:
    /// round tail cap → shaft edge → head wing → tip → other wing → other shaft edge → back to the tail.
    /// The shaft is a rectangle of width `w` that ends exactly on the head base, so nothing overlaps.
    /// Short drags shrink the head to the drag length (never inverted); below ~2 pt there is no arrow.
    static func arrowPath(from s: CGPoint, to e: CGPoint, width w: CGFloat) -> CGPath? {
        let dx = e.x - s.x, dy = e.y - s.y
        let len = hypot(dx, dy)
        guard len >= 2 else { return nil }
        let ux = dx / len, uy = dy / len
        let px = -uy, py = ux                    // left-hand normal
        let hw = w / 2
        let headLen = min(max(10, w * 3 + 8), len)
        // The head must stay wider than the shaft, even when clamped by a short drag.
        let headHalf = max(headLen * 0.45, hw + 1.5)
        let base = CGPoint(x: e.x - ux * headLen, y: e.y - uy * headLen)
        func pt(_ o: CGPoint, _ along: CGFloat, _ side: CGFloat) -> CGPoint {
            CGPoint(x: o.x + ux * along + px * side, y: o.y + uy * along + py * side)
        }
        let path = CGMutablePath()
        let shaftLen = len - headLen
        if shaftLen > 0.5 {
            path.move(to: pt(base, 0, hw))                       // shaft, left edge at the head base
            path.addLine(to: pt(s, 0, hw))                       // left edge at the tail
            path.addRelativeArc(center: s, radius: hw,           // round tail cap, through -u
                                startAngle: atan2(py, px), delta: .pi)
            path.addLine(to: pt(base, 0, -hw))                   // right edge back to the head base
            path.addLine(to: pt(base, 0, -headHalf))             // right wing
            path.addLine(to: e)                                  // tip
            path.addLine(to: pt(base, 0, headHalf))              // left wing
        } else {
            // Too short for a shaft: head only.
            path.move(to: pt(base, 0, -headHalf))
            path.addLine(to: e)
            path.addLine(to: pt(base, 0, headHalf))
        }
        path.closeSubpath()
        return path
    }

    static func rect(from s: CGPoint, to e: CGPoint, square: Bool) -> CGRect {
        var dx = e.x - s.x, dy = e.y - s.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        return CGRect(x: s.x, y: s.y, width: dx, height: dy).standardized
    }

    static func ellipsePath(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }

    /// Count-marker diameter: ~30 pt at the default 4 pt width, growing moderately with the stroke width.
    static func markerDiameter(width w: CGFloat) -> CGFloat { 27 + 0.75 * w }

    /// Speech-bubble marker as ONE closed outline (non-zero fill, no overlapping subpaths):
    /// the circle's major arc, then straight to the tail tip `tip`, then back to the arc start.
    /// The bubble sits up-right of the tip (centre ~1.85 r away) and flips left/down so it stays inside `bounds`.
    static func markerBubble(tip p: CGPoint, diameter d: CGFloat, in bounds: CGRect) -> (path: CGPath, center: CGPoint) {
        let r = d / 2
        let dist = r * 1.85
        let k = dist * CGFloat(0.5).squareRoot()        // 45° offset on each axis
        let margin: CGFloat = 6                          // white border + shadow
        var sx: CGFloat = 1, sy: CGFloat = 1             // AppKit: +y is up
        if p.x + k + r + margin > bounds.maxX { sx = -1 }
        if p.y + k + r + margin > bounds.maxY { sy = -1 }
        let c = CGPoint(x: p.x + sx * k, y: p.y + sy * k)
        let theta = atan2(p.y - c.y, p.x - c.x)          // from the centre towards the tip
        let alpha: CGFloat = 0.48                        // half-angle of the tail base on the circle
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x + r * cos(theta + alpha), y: c.y + r * sin(theta + alpha)))
        path.addRelativeArc(center: c, radius: r, startAngle: theta + alpha, delta: 2 * .pi - 2 * alpha)
        path.addLine(to: p)
        path.closeSubpath()
        return (path, c)
    }

    /// Bold number as glyph outlines, centred (by its ink bounds) on `center` and fitted inside a circle of diameter `d`.
    static func markerNumberPath(_ n: Int, center c: CGPoint, diameter d: CGFloat) -> CGPath {
        let text = String(n)
        func glyphs(_ size: CGFloat) -> CGPath {
            let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
                ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attr)
            let path = CGMutablePath()
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
                let count = CTRunGetGlyphCount(run)
                var gs = [CGGlyph](repeating: 0, count: count)
                var ps = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &gs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &ps)
                for i in 0..<count {
                    if let g = CTFontCreatePathForGlyph(runFont, gs[i], nil) {
                        path.addPath(g, transform: CGAffineTransform(translationX: ps[i].x, y: ps[i].y))
                    }
                }
            }
            return path
        }
        var size = d * 0.56
        var path = glyphs(size)
        let maxW = d * 0.64
        let w = path.boundingBoxOfPath.width
        if w > maxW { size *= maxW / w; path = glyphs(size) }  // 10+: shrink to stay inside the circle
        let b = path.boundingBoxOfPath
        var t = CGAffineTransform(translationX: c.x - b.midX, y: c.y - b.midY)
        return path.copy(using: &t) ?? path
    }

    static func roundedRectPath(_ r: CGRect, radius: CGFloat) -> CGPath {
        let rad = max(0, min(radius, r.width / 2, r.height / 2))
        return CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    }

    /// Quadratic midpoint smoothing.
    static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 { path.addLine(to: first); return path }
        if pts.count == 2 { path.addLine(to: pts[1]); return path }
        for i in 1..<pts.count {
            let p0 = pts[i - 1], p1 = pts[i]
            path.addQuadCurve(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2), control: p0)
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }
}
