import AppKit

/// The editing surface.
///
/// Three jobs beyond what `NSTextView` does: keep the column at a readable
/// measure, hide Markdown syntax that isn't being edited, and draw the
/// ornaments that replace it — bullets, checkboxes, quote bars, code panels.
final class WritingTextView: NSTextView {

    var typography = Typography(base: Preferences.defaultFontSize) {
        didSet { updateInsets() }
    }

    var decorations: [BlockDecoration] = [] {
        didSet { needsDisplay = true }
    }

    /// Syntax eligible to be hidden, each with the range that reveals it.
    var conceals: [ConcealRange] = [] {
        // A full re-layout is only warranted when the syntax map actually moved;
        // re-running the highlighter often produces an identical map.
        didSet { refreshConcealment(force: conceals != oldValue) }
    }

    /// Called when the effective appearance flips, so the owner can re-run the
    /// highlighter — dynamic colors redraw themselves, but decorations don't.
    var onAppearanceChange: (() -> Void)?

    /// Character indexes currently generating no glyphs. (Named to avoid
    /// colliding with NSView's ObjC `hidden` property.)
    private var concealedIndexes = IndexSet()
    private var isRefreshing = false

    // MARK: - Measure

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    /// Horizontal inset centers the column; vertical inset gives the first line
    /// room under the (hidden) titlebar.
    private func updateInsets() {
        let horizontal = max(28, (bounds.width - typography.maxMeasure) / 2)
        let inset = NSSize(width: horizontal, height: typography.verticalPadding)
        if abs(inset.width - textContainerInset.width) > 0.5
            || abs(inset.height - textContainerInset.height) > 0.5 {
            textContainerInset = inset
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
        needsDisplay = true
    }

    // MARK: - Concealment

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        refreshConcealment()
        syncTypingAttributes()
    }

    /// The caret is drawn at the height of `typingAttributes`, and the next
    /// character inherits them. Forcing them to the body font makes the caret
    /// shrink on a heading and the typed character jump when the highlighter
    /// catches up — so instead they're taken from the text at the caret.
    func syncTypingAttributes() {
        guard let textStorage, textStorage.length > 0 else {
            typingAttributes = [
                .font: typography.body,
                .foregroundColor: Palette.text
            ]
            return
        }

        let string = textStorage.string as NSString
        let caret = min(max(selectedRange().location, 0), textStorage.length)

        // Prefer the character to the left — that's what you're continuing.
        // At the start of a line there is nothing to continue, so look right.
        var index = min(caret, textStorage.length - 1)
        if caret > 0, string.character(at: caret - 1) != 0x0A {
            index = caret - 1
        }

        var attributes = textStorage.attributes(at: index, effectiveRange: nil)
        // Span decorations shouldn't leak into whatever gets typed next.
        attributes.removeValue(forKey: .strikethroughStyle)
        attributes.removeValue(forKey: .underlineStyle)
        attributes.removeValue(forKey: .underlineColor)
        typingAttributes = attributes
    }

    /// Recomputes which characters are hidden and invalidates only what moved.
    func refreshConcealment(force: Bool = false) {
        guard !isRefreshing, let layoutManager, let textStorage else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let selection = selectedRange()
        let length = textStorage.length

        var next = IndexSet()
        for conceal in conceals {
            guard conceal.range.location >= 0,
                  NSMaxRange(conceal.range) <= length,
                  conceal.range.length > 0
            else { continue }
            if !revealed(conceal.reveal, by: selection) {
                next.insert(integersIn: conceal.range.lowerBound..<conceal.range.upperBound)
            }
        }

        guard force || next != concealedIndexes else { return }

        let moved = force
            ? IndexSet(integersIn: 0..<max(length, 1))
            : next.symmetricDifference(concealedIndexes)
        concealedIndexes = next

        for range in moved.rangeView {
            let characters = NSRange(
                location: range.lowerBound,
                length: min(range.count, max(0, length - range.lowerBound))
            )
            guard characters.length > 0 else { continue }
            layoutManager.invalidateGlyphs(
                forCharacterRange: characters,
                changeInLength: 0,
                actualCharacterRange: nil
            )
            layoutManager.invalidateLayout(forCharacterRange: characters, actualCharacterRange: nil)
        }
        needsDisplay = true
    }

    /// A caret sitting at either edge counts as inside, so typing at the end of
    /// a line keeps its syntax visible.
    private func revealed(_ reveal: NSRange, by selection: NSRange) -> Bool {
        NSMaxRange(selection) >= reveal.location && selection.location <= NSMaxRange(reveal)
    }

    // MARK: - Ornament drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let contentWidth = textContainer.size.width

        for decoration in decorations {
            guard let box = boundingBox(for: decoration.range, layoutManager: layoutManager, container: textContainer)
            else { continue }
            let frame = box.offsetBy(dx: origin.x, dy: origin.y)

            switch decoration.kind {
            case .codeBlock:
                let panel = NSRect(
                    x: origin.x - 6,
                    y: frame.minY - 4,
                    width: contentWidth + 12,
                    height: frame.height + 8
                )
                guard panel.intersects(rect) else { continue }
                Palette.codeBackground.setFill()
                NSBezierPath(roundedRect: panel, xRadius: 7, yRadius: 7).fill()

            case .quote:
                let bar = NSRect(x: origin.x + 2, y: frame.minY, width: 3, height: frame.height)
                guard bar.intersects(rect) else { continue }
                Palette.quoteBar.setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()

            case let .bullet(indent, level):
                guard let baseline = firstBaseline(for: decoration.range, layoutManager: layoutManager, container: textContainer)
                else { continue }
                let size: CGFloat = level == 0 ? 5 : 4.5
                let dot = NSRect(
                    x: origin.x + indent + typography.base * 0.25,
                    y: origin.y + baseline - typography.base * 0.3 - size / 2,
                    width: size,
                    height: size
                )
                guard dot.intersects(rect) else { continue }
                Palette.bullet.setFill()
                // Second-level bullets are hollow, as in every outliner.
                if level == 0 {
                    NSBezierPath(ovalIn: dot).fill()
                } else {
                    let path = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
                    path.lineWidth = 1
                    Palette.bullet.setStroke()
                    path.stroke()
                }

            case let .checkbox(indent, checked):
                guard let baseline = firstBaseline(for: decoration.range, layoutManager: layoutManager, container: textContainer)
                else { continue }
                let side = typography.base * 0.72
                let box = NSRect(
                    x: origin.x + indent + typography.base * 0.1,
                    y: origin.y + baseline - typography.base * 0.32 - side / 2,
                    width: side,
                    height: side
                )
                guard box.intersects(rect) else { continue }
                drawCheckbox(in: box, checked: checked)

            case .rule:
                let line = NSRect(
                    x: origin.x,
                    y: (frame.midY - 0.5).rounded(),
                    width: contentWidth,
                    height: 1
                )
                guard line.intersects(rect) else { continue }
                Palette.rule.setFill()
                line.fill()
            }
        }
    }

    private func drawCheckbox(in box: NSRect, checked: Bool) {
        let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
        outline.lineWidth = 1.4

        if checked {
            Palette.accent.setFill()
            outline.fill()
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + box.width * 0.26, y: box.minY + box.height * 0.52))
            tick.line(to: NSPoint(x: box.minX + box.width * 0.44, y: box.minY + box.height * 0.70))
            tick.line(to: NSPoint(x: box.minX + box.width * 0.76, y: box.minY + box.height * 0.30))
            tick.lineWidth = 1.8
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            Palette.background.setStroke()
            tick.stroke()
        } else {
            Palette.quoteBar.setStroke()
            outline.stroke()
        }
    }

    // MARK: - Geometry helpers

    private func boundingBox(
        for range: NSRange,
        layoutManager: NSLayoutManager,
        container: NSTextContainer
    ) -> NSRect? {
        guard let textStorage, NSMaxRange(range) <= textStorage.length else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }
        return layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
    }

    /// Baseline of a line's first fragment, in container coordinates. Ornaments
    /// hang off the baseline rather than the fragment box, so they sit with the
    /// text instead of floating in the leading.
    private func firstBaseline(
        for range: NSRange,
        layoutManager: NSLayoutManager,
        container: NSTextContainer
    ) -> CGFloat? {
        guard let textStorage, range.location < textStorage.length else { return nil }
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let location = layoutManager.location(forGlyphAt: glyphIndex)
        return fragment.minY + location.y
    }

    // MARK: - Selection

    /// Softer, warmer selection than the system accent, matching the palette.
    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { [.backgroundColor: Palette.selection] }
        set { super.selectedTextAttributes = newValue }
    }
}

// MARK: - Glyph suppression

extension WritingTextView: NSLayoutManagerDelegate {

    /// Where concealment actually happens. Marking a glyph `.null` removes it
    /// from layout entirely — no width, no draw — while the character stays in
    /// the text storage. That is what lets the document read as rendered
    /// Markdown while saving as plain Markdown.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard !concealedIndexes.isEmpty, glyphRange.length > 0 else { return 0 }

        var updated = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        var changed = false
        for offset in 0..<glyphRange.length where concealedIndexes.contains(characterIndexes[offset]) {
            updated[offset].insert(.null)
            changed = true
        }
        guard changed else { return 0 }

        updated.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            layoutManager.setGlyphs(
                glyphs,
                properties: base,
                characterIndexes: characterIndexes,
                font: font,
                forGlyphRange: glyphRange
            )
        }
        return glyphRange.length
    }
}
