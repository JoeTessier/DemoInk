import AppKit
import CoreText
import QuartzCore

// Text tool. The label is ONE CAShapeLayer of glyph outlines (bold system font, ink colour, the usual shadow),
// rebuilt on every edit. The live editor and the committed label are the same layer: at commit only the caret
// sublayer is removed, so there is never a second copy (no ghost) and no system text field (no dark-mode box).
// Keyboard input arrives through NSTextInputClient (dead keys / IME included) while OverlayController keeps the
// drawing-mode hotkeys suspended and the app active for the duration of the entry.

extension Geometry {
    /// Label size from the stroke width: 28 pt at width 8, 17.5 … 52 pt over the 1 … 24 range.
    static func textFontSize(width w: CGFloat) -> CGFloat { 16 + 1.5 * w }

    static func textFont(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    struct TextLayout {
        let path: CGPath      // glyphs (+ marked-text underline), canvas coordinates
        let frame: CGRect     // text block on the canvas, after edge clamping
        let caret: CGRect
    }

    /// Lays out `text` (lines split on "\n") with its first line vertically centred on `anchor`, growing right and
    /// down. The block is shifted left / up so it stays `margin` inside `bounds` (right and bottom edges first).
    static func textLayout(_ text: String, fontSize: CGFloat, anchor: CGPoint, in bounds: CGRect,
                           caret: Int, marked: NSRange) -> TextLayout {
        let font = textFont(size: fontSize)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let lineH = ceil(ascent + descent + max(CTFontGetLeading(font), fontSize * 0.08))
        let caretW = max(2, (fontSize * 0.07).rounded())
        let ns = text as NSString
        let parts = ns.components(separatedBy: "\n")
        var lines: [(line: CTLine, start: Int, length: Int, width: CGFloat)] = []
        var start = 0
        for part in parts {
            let attr = NSAttributedString(string: part, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(attr)
            let len = (part as NSString).length
            lines.append((line, start, len, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))))
            start += len + 1
        }
        let blockW = max(lines.map { $0.width }.max() ?? 0, 0) + caretW
        let blockH = CGFloat(lines.count) * lineH
        let margin: CGFloat = 10 // shadow + breathing room
        var x = anchor.x
        var top = anchor.y + lineH / 2
        x = max(min(x, bounds.maxX - margin - blockW), bounds.minX + margin)
        top = min(max(top, bounds.minY + margin + blockH), bounds.maxY - margin)

        let path = CGMutablePath()
        var caretRect = CGRect(x: x, y: top - ascent - descent, width: caretW, height: ascent + descent)
        for (i, l) in lines.enumerated() {
            let baseline = top - ascent - CGFloat(i) * lineH
            path.addPath(glyphPath(l.line), transform: CGAffineTransform(translationX: x, y: baseline))
            if caret >= l.start && caret <= l.start + l.length {
                let off = CTLineGetOffsetForStringIndex(l.line, caret - l.start, nil)
                caretRect = CGRect(x: x + off - caretW / 2, y: baseline - descent, width: caretW, height: ascent + descent)
            }
            if marked.location != NSNotFound, marked.length > 0 {
                let a = max(marked.location, l.start), b = min(NSMaxRange(marked), l.start + l.length)
                if a < b {
                    let xa = CTLineGetOffsetForStringIndex(l.line, a - l.start, nil)
                    let xb = CTLineGetOffsetForStringIndex(l.line, b - l.start, nil)
                    let h = max(1.5, fontSize * 0.06)
                    path.addRect(CGRect(x: x + xa, y: baseline - descent * 0.6 - h, width: xb - xa, height: h))
                }
            }
        }
        return TextLayout(path: path, frame: CGRect(x: x, y: top - blockH, width: blockW, height: blockH), caret: caretRect)
    }
}

/// The label being typed on one canvas.
final class TextEntry {
    let layer: CAShapeLayer
    let caretLayer = CALayer()
    let anchor: CGPoint
    let text = NSMutableString()
    var caret = 0                                             // UTF-16 index
    var marked = NSRange(location: NSNotFound, length: 0)    // dead-key / IME composition
    private(set) var fontSize: CGFloat = 0
    private(set) var layout: Geometry.TextLayout?

    init(layer: CAShapeLayer, anchor: CGPoint) {
        self.layer = layer
        self.anchor = anchor
    }

    var string: String { text as String }
    var length: Int { text.length }

    func relayout(in bounds: CGRect, showCaret: Bool) {
        fontSize = Geometry.textFontSize(width: Settings.shared.width)
        let l = Geometry.textLayout(string, fontSize: fontSize, anchor: anchor, in: bounds, caret: caret,
                                    marked: showCaret ? marked : NSRange(location: NSNotFound, length: 0))
        layout = l
        let color = Settings.shared.color.color.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.path = l.path
        layer.fillColor = color
        caretLayer.frame = l.caret
        caretLayer.backgroundColor = color
        CATransaction.commit()
        if showCaret { restartBlink() }
    }

    /// Caret visible right after each edit, then blinking.
    private func restartBlink() {
        caretLayer.removeAnimation(forKey: "blink")
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [1, 0]
        a.keyTimes = [0, 0.5]
        a.calculationMode = .discrete
        a.duration = 1.06
        a.repeatCount = .infinity
        a.beginTime = CACurrentMediaTime() + 0.5
        a.fillMode = .backwards
        caretLayer.add(a, forKey: "blink")
    }

    // MARK: Editing primitives (UTF-16 indices, composed-character safe)

    private var lineRanges: [NSRange] {
        var out: [NSRange] = []
        var start = 0
        for part in string.components(separatedBy: "\n") {
            let len = (part as NSString).length
            out.append(NSRange(location: start, length: len))
            start += len + 1
        }
        return out
    }

    private var currentLine: (index: Int, range: NSRange) {
        let ranges = lineRanges
        let i = ranges.firstIndex { caret >= $0.location && caret <= NSMaxRange($0) } ?? ranges.count - 1
        return (i, ranges[i])
    }

    func insert(_ s: String) {
        // Normalise line breaks, drop other control characters (tabs become spaces).
        let clean = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .unicodeScalars.filter { $0 == "\n" || $0.value >= 0x20 && $0.value != 0x7F }
        let str = String(String.UnicodeScalarView(clean))
        let r = marked.location != NSNotFound ? marked : NSRange(location: caret, length: 0)
        text.replaceCharacters(in: clampRange(r), with: str)
        caret = clampRange(r).location + (str as NSString).length
        marked = NSRange(location: NSNotFound, length: 0)
    }

    func setMarked(_ s: String, selected: NSRange, replacement: NSRange) {
        var r = NSRange(location: caret, length: 0)
        if marked.location != NSNotFound { r = marked } else if replacement.location != NSNotFound { r = replacement }
        r = clampRange(r)
        text.replaceCharacters(in: r, with: s)
        let len = (s as NSString).length
        marked = len > 0 ? NSRange(location: r.location, length: len) : NSRange(location: NSNotFound, length: 0)
        caret = r.location + min(len, max(0, selected.location + selected.length))
    }

    func clampRange(_ r: NSRange) -> NSRange {
        let loc = min(max(0, r.location), length)
        return NSRange(location: loc, length: min(max(0, r.length), length - loc))
    }

    func moveLeft() { if caret > 0 { caret = text.rangeOfComposedCharacterSequence(at: caret - 1).location } }
    func moveRight() { if caret < length { caret = NSMaxRange(text.rangeOfComposedCharacterSequence(at: caret)) } }

    func moveVertically(_ delta: Int) {
        let ranges = lineRanges
        let (i, r) = currentLine
        let j = i + delta
        guard ranges.indices.contains(j) else { caret = delta < 0 ? 0 : length; return }
        caret = ranges[j].location + min(caret - r.location, ranges[j].length)
        if caret > 0 && caret < length { caret = text.rangeOfComposedCharacterSequence(at: caret).location }
    }

    func moveToLineStart() { caret = currentLine.range.location }
    func moveToLineEnd() { caret = NSMaxRange(currentLine.range) }

    private func isSpace(_ i: Int) -> Bool {
        guard let u = UnicodeScalar(text.character(at: i)) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(u) || CharacterSet.punctuationCharacters.contains(u)
    }

    func wordLeft() -> Int {
        var i = caret
        while i > 0 && isSpace(i - 1) { i -= 1 }
        while i > 0 && !isSpace(i - 1) { i -= 1 }
        return i
    }

    func wordRight() -> Int {
        var i = caret
        while i < length && isSpace(i) { i += 1 }
        while i < length && !isSpace(i) { i += 1 }
        return i
    }

    func deleteBackward() {
        guard caret > 0 else { return }
        let r = text.rangeOfComposedCharacterSequence(at: caret - 1)
        text.deleteCharacters(in: r)
        caret = r.location
    }

    func deleteForward() {
        guard caret < length else { return }
        text.deleteCharacters(in: text.rangeOfComposedCharacterSequence(at: caret))
    }

    func delete(to target: Int) {
        let a = min(target, caret), b = max(target, caret)
        text.deleteCharacters(in: NSRange(location: a, length: b - a))
        caret = a
    }
}

// MARK: - Canvas side: start / finish, NSTextInputClient

extension CanvasView: NSTextInputClient {
    var isEditingText: Bool { textEntry != nil }

    /// Starts a label at `p` (canvas coordinates). Focus and hotkeys are handled by the controller.
    func startText(at p: CGPoint) {
        let l = CAShapeLayer()
        l.contentsScale = scale
        l.frame = bounds
        l.actions = ["path": NSNull(), "fillColor": NSNull(), "hidden": NSNull(), "opacity": NSNull(), "sublayers": NSNull()]
        l.strokeColor = nil
        l.fillRule = .nonZero
        setShadow(l)
        let e = TextEntry(layer: l, anchor: p)
        e.caretLayer.contentsScale = scale
        e.caretLayer.actions = ["position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull(), "opacity": NSNull()]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.addSublayer(e.caretLayer)
        shapesContainer.addSublayer(l)
        CATransaction.commit()
        textEntry = e
        e.relayout(in: bounds, showCaret: true)
    }

    /// Re-applies colour / size (colour hotkey, scroll wheel) to the label being typed.
    func refreshText() { textEntry?.relayout(in: bounds, showCaret: true) }

    /// Ends the entry. Commit keeps a non-blank label as a static layer in the undo history; otherwise it is removed.
    /// Returns true if a label was committed.
    @discardableResult
    func finishText(commit: Bool) -> Bool {
        guard let e = textEntry else { return false }
        if e.marked.location != NSNotFound { inputContext?.discardMarkedText(); e.marked = NSRange(location: NSNotFound, length: 0) }
        textEntry = nil
        let keep = commit && !e.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        e.caretLayer.removeAllAnimations()
        e.caretLayer.removeFromSuperlayer()
        if keep {
            e.relayout(in: bounds, showCaret: false) // final glyphs, no marked-text underline
            recordText(e.layer)
        } else {
            e.layer.removeFromSuperlayer()
        }
        CATransaction.commit()
        NSLog("DemoInk: text entry %@ (%d chars)", keep ? "committed" : "dropped", e.length)
        return keep
    }

    /// Keyboard while a label is being typed. Return commits, ⇧/⌥Return adds a line, Esc cancels; the rest goes
    /// through the input context (dead keys, IME, standard editing commands).
    func textKeyDown(_ event: NSEvent) {
        guard let e = textEntry else { return }
        if e.marked.location != NSNotFound { _ = inputContext?.handleEvent(event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case 53: // Esc
            controller?.endTextEntry(commit: false)
        case 36, 76: // Return, keypad Enter
            if flags.contains(.shift) || flags.contains(.option) { e.insert("\n"); e.relayout(in: bounds, showCaret: true) }
            else { controller?.endTextEntry(commit: true) }
        default:
            if flags.contains(.command) { return }
            if inputContext?.handleEvent(event) != true { interpretKeyEvents([event]) }
        }
    }

    /// ⌘V pastes plain text into the label being typed.
    func pasteText() {
        guard let e = textEntry, let s = NSPasteboard.general.string(forType: .string) else { return }
        e.insert(s)
        e.relayout(in: bounds, showCaret: true)
    }

    // NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let e = textEntry else { return }
        let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if e.marked.location == NSNotFound, replacementRange.location != NSNotFound {
            e.marked = e.clampRange(replacementRange) // replace exactly what the input method asked for
        }
        e.insert(s)
        e.relayout(in: bounds, showCaret: true)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let e = textEntry else { return }
        let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        e.setMarked(s, selected: selectedRange, replacement: replacementRange)
        e.relayout(in: bounds, showCaret: true)
    }

    func unmarkText() {
        guard let e = textEntry else { return }
        e.marked = NSRange(location: NSNotFound, length: 0)
        e.relayout(in: bounds, showCaret: true)
    }

    func selectedRange() -> NSRange {
        guard let e = textEntry else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: e.caret, length: 0)
    }

    func markedRange() -> NSRange { textEntry?.marked ?? NSRange(location: NSNotFound, length: 0) }
    func hasMarkedText() -> Bool { (textEntry?.marked.location ?? NSNotFound) != NSNotFound }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let e = textEntry else { return nil }
        let r = e.clampRange(range)
        actualRange?.pointee = r
        return NSAttributedString(string: e.text.substring(with: r))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let e = textEntry, let caret = e.layout?.caret, let window = window else { return .zero }
        return window.convertToScreen(convert(caret, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int { textEntry?.caret ?? NSNotFound }

    override func doCommand(by selector: Selector) {
        guard let e = textEntry else { super.doCommand(by: selector); return }
        switch selector {
        case #selector(deleteBackward(_:)): e.deleteBackward()
        case #selector(deleteForward(_:)): e.deleteForward()
        case #selector(deleteWordBackward(_:)): e.delete(to: e.wordLeft())
        case #selector(deleteWordForward(_:)): e.delete(to: e.wordRight())
        case #selector(deleteToBeginningOfLine(_:)): e.delete(to: { e.moveToLineStart(); return e.caret }())
        case #selector(moveLeft(_:)): e.moveLeft()
        case #selector(moveRight(_:)): e.moveRight()
        case #selector(moveUp(_:)): e.moveVertically(-1)
        case #selector(moveDown(_:)): e.moveVertically(1)
        case #selector(moveWordLeft(_:)): e.caret = e.wordLeft()
        case #selector(moveWordRight(_:)): e.caret = e.wordRight()
        case #selector(moveToBeginningOfLine(_:)), #selector(moveToLeftEndOfLine(_:)),
             #selector(moveToBeginningOfParagraph(_:)): e.moveToLineStart()
        case #selector(moveToEndOfLine(_:)), #selector(moveToRightEndOfLine(_:)),
             #selector(moveToEndOfParagraph(_:)): e.moveToLineEnd()
        case #selector(moveToBeginningOfDocument(_:)): e.caret = 0
        case #selector(moveToEndOfDocument(_:)): e.caret = e.length
        case #selector(insertLineBreak(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)),
             #selector(insertParagraphSeparator(_:)): e.insert("\n")
        case #selector(insertNewline(_:)): controller?.endTextEntry(commit: true); return
        case #selector(cancelOperation(_:)): controller?.endTextEntry(commit: false); return
        default: return // no selection model: other commands are ignored (and do not beep)
        }
        e.relayout(in: bounds, showCaret: true)
    }
}
