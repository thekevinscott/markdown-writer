import AppKit

/// A background shape the text view paints behind the glyphs: code panels,
/// quote bars, rules, list bullets, checkboxes. None of these can be expressed
/// as text attributes — attribute backgrounds hug glyphs and look ragged, and
/// there is no attribute that draws a bullet.
struct BlockDecoration {
    enum Kind {
        case codeBlock
        case quote
        case rule
        case bullet(indent: CGFloat, level: Int)
        case checkbox(indent: CGFloat, checked: Bool)
    }

    let kind: Kind
    /// Character range whose laid-out rect anchors the drawing.
    let range: NSRange
}

/// Syntax that is hidden from layout until the caret enters `reveal`.
///
/// This is what makes the document *look* rendered while remaining plain
/// Markdown in memory: the characters are still there, they just generate no
/// glyphs. Editing a line brings its own syntax back, so nothing is ever
/// invisible while you're working on it.
struct ConcealRange: Equatable {
    let range: NSRange
    let reveal: NSRange
}

struct HighlightResult {
    var decorations: [BlockDecoration] = []
    var conceals: [ConcealRange] = []
}

/// Styles GitHub-flavored Markdown in place. The buffer is never rewritten —
/// what you type is exactly what gets saved.
enum MarkdownHighlighter {

    // MARK: - Patterns

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals; a failure here is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static let heading = regex(#"^(#{1,6})([ \t]+)(.*)$"#)
    private static let fence = regex(#"^[ \t]{0,3}(`{3,}|~{3,})(.*)$"#)
    private static let quote = regex(#"^([ \t]{0,3}(?:>[ \t]?)+)"#)
    private static let bulletList = regex(#"^([ \t]*)([-*+])([ \t]+)"#)
    private static let orderedList = regex(#"^([ \t]*)(\d{1,9}[.)])([ \t]+)"#)
    private static let task = regex(#"^([ \t]*)(?:[-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\])([ \t]+)"#)
    private static let thematicBreak = regex(#"^[ \t]{0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})$"#)
    private static let tableDelimiter = regex(#"^[ \t]*\|?[ \t]*:?-{2,}:?[ \t]*(\|[ \t]*:?-{2,}:?[ \t]*)*\|?[ \t]*$"#)

    private static let codeSpan = regex(#"(`+)([^`\n]+)(\1)"#)
    private static let boldStar = regex(#"(\*\*)(?=\S)([^\n]+?)(?<=\S)(\*\*)"#)
    private static let boldUnderscore = regex(#"(?<![\w_])(__)(?=\S)([^\n]+?)(?<=\S)(__)(?![\w_])"#)
    private static let italicStar = regex(#"(?<![\*\w])(\*)(?=[^\s\*])([^\*\n]+)(?<=[^\s\*])(\*)(?![\*\w])"#)
    private static let italicUnderscore = regex(#"(?<![_\w])(_)(?=[^\s_])([^_\n]+)(?<=[^\s_])(_)(?![_\w])"#)
    private static let strikethrough = regex(#"(~~)(?=\S)([^~\n]+)(?<=\S)(~~)"#)
    private static let link = regex(#"(!?\[)([^\]\n]*)(\]\([^)\s]*(?:[ \t]+"[^"\n]*")?\))"#)
    private static let autolink = regex(#"(<)(https?://[^>\s]+)(>)"#)
    private static let bareURL = regex(#"(?<![\(\[<"])https?://[^\s\)\]>"]+"#)

    // MARK: - Entry point

    /// Rewrites every attribute in `storage` and returns what the text view
    /// needs to paint and to conceal.
    @discardableResult
    static func apply(to storage: NSTextStorage, typography: Typography) -> HighlightResult {
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)

        var result = HighlightResult()

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(baseAttributes(typography), range: full)
        guard text.length > 0 else { return result }

        let lines = scanLines(text)
        let classes = classify(lines, text: text)
        let blocks = codeBlockRanges(lines: lines, classes: classes)

        for (index, line) in lines.enumerated() {
            switch classes[index] {
            case .fenceMarker:
                storage.addAttributes(
                    [.font: typography.code, .foregroundColor: Palette.marker],
                    range: line.content
                )
                storage.addAttribute(.paragraphStyle, value: codeParagraphStyle(typography), range: line.enclosing)
                if line.content.length > 0 {
                    // The whole fence line vanishes; the panel that replaces it
                    // is drawn by the text view. Reveal the fences whenever the
                    // caret is anywhere in the block.
                    result.conceals.append(
                        ConcealRange(range: line.content, reveal: blocks[index] ?? line.content)
                    )
                }

            case .code:
                storage.addAttributes(
                    [.font: typography.code, .foregroundColor: Palette.codeText],
                    range: line.content
                )
                storage.addAttribute(.paragraphStyle, value: codeParagraphStyle(typography), range: line.enclosing)

            case .table:
                storage.addAttribute(.font, value: typography.code, range: line.content)
                storage.addAttribute(.paragraphStyle, value: tableParagraphStyle(typography), range: line.enclosing)
                styleInline(storage, in: line.content, reveal: line.content, typography: typography, result: &result)

            case .rule:
                storage.addAttribute(.font, value: typography.code, range: line.content)
                storage.addAttribute(.foregroundColor, value: Palette.marker, range: line.content)
                result.decorations.append(BlockDecoration(kind: .rule, range: line.enclosing))
                result.conceals.append(ConcealRange(range: line.content, reveal: line.content))

            case .body:
                styleBodyLine(storage, line: line, typography: typography, result: &result)
            }
        }

        result.decorations.append(contentsOf: codePanels(lines: lines, classes: classes))
        return result
    }

    // MARK: - Paragraph styles

    private static func baseAttributes(_ typography: Typography) -> [NSAttributedString.Key: Any] {
        [
            .font: typography.body,
            .foregroundColor: Palette.text,
            .paragraphStyle: bodyParagraphStyle(typography)
        ]
    }

    private static func bodyParagraphStyle(_ typography: Typography) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = typography.lineHeightMultiple
        style.paragraphSpacing = typography.paragraphSpacing
        return style
    }

    private static func codeParagraphStyle(_ typography: Typography) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.28
        style.paragraphSpacing = 0
        style.firstLineHeadIndent = 16
        style.headIndent = 16
        return style
    }

    private static func tableParagraphStyle(_ typography: Typography) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.35
        style.paragraphSpacing = 0
        return style
    }

    private static func headingParagraphStyle(_ typography: Typography, level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.16
        style.paragraphSpacingBefore = typography.base * (level <= 2 ? 1.5 : 1.1)
        style.paragraphSpacing = typography.base * 0.3
        return style
    }

    private static func quoteParagraphStyle(_ typography: Typography) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = typography.lineHeightMultiple
        style.paragraphSpacing = typography.paragraphSpacing * 0.35
        style.firstLineHeadIndent = 24
        style.headIndent = 24
        return style
    }

    /// Hanging indent: the bullet or number sits in the margin, wrapped lines
    /// align with the text, not the marker.
    private static func listParagraphStyle(
        _ typography: Typography,
        indent: CGFloat,
        hanging: CGFloat
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = typography.lineHeightMultiple
        style.paragraphSpacing = typography.paragraphSpacing * 0.3
        style.firstLineHeadIndent = indent + hanging
        style.headIndent = indent + hanging
        return style
    }

    // MARK: - Line scanning

    private struct Line {
        /// Without the terminator — what regexes run against.
        let content: NSRange
        /// With the terminator — what paragraph styles apply to.
        let enclosing: NSRange
    }

    private enum LineClass {
        case body
        case code
        case fenceMarker
        case table
        case rule
    }

    private static func scanLines(_ text: NSString) -> [Line] {
        var lines: [Line] = []
        let full = NSRange(location: 0, length: text.length)
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, range, enclosing, _ in
            lines.append(Line(content: range, enclosing: enclosing))
        }
        return lines
    }

    private static func classify(_ lines: [Line], text: NSString) -> [LineClass] {
        var classes = [LineClass](repeating: .body, count: lines.count)

        // Fenced code wins over everything else.
        var openFence: String?
        for (index, line) in lines.enumerated() {
            let raw = text.substring(with: line.content)
            let local = NSRange(location: 0, length: (raw as NSString).length)
            let match = fence.firstMatch(in: raw, range: local)
            let marker = match.map { (raw as NSString).substring(with: $0.range(at: 1)) }

            if let open = openFence {
                if let marker, marker.first == open.first, marker.count >= open.count {
                    classes[index] = .fenceMarker
                    openFence = nil
                } else {
                    classes[index] = .code
                }
            } else if let marker {
                classes[index] = .fenceMarker
                openFence = marker
            }
        }

        for (index, line) in lines.enumerated() where classes[index] == .body {
            let raw = text.substring(with: line.content)
            let local = NSRange(location: 0, length: (raw as NSString).length)
            if thematicBreak.firstMatch(in: raw, range: local) != nil {
                classes[index] = .rule
            }
        }

        // A table is a delimiter row plus the contiguous pipe-bearing lines
        // around it. Requiring the delimiter keeps prose containing a pipe from
        // being mistaken for one.
        for index in lines.indices where classes[index] == .body {
            let raw = text.substring(with: lines[index].content)
            let local = NSRange(location: 0, length: (raw as NSString).length)
            guard raw.contains("-"), raw.contains("|"),
                  tableDelimiter.firstMatch(in: raw, range: local) != nil,
                  index > 0, classes[index - 1] == .body,
                  text.substring(with: lines[index - 1].content).contains("|")
            else { continue }

            classes[index] = .table
            classes[index - 1] = .table
            var next = index + 1
            while next < lines.count,
                  classes[next] == .body,
                  text.substring(with: lines[next].content).contains("|") {
                classes[next] = .table
                next += 1
            }
        }

        return classes
    }

    /// Maps each fence/code line index to the character range of its whole
    /// block, so entering the block anywhere reveals its fences.
    private static func codeBlockRanges(lines: [Line], classes: [LineClass]) -> [Int: NSRange] {
        var map: [Int: NSRange] = [:]
        for panel in codePanels(lines: lines, classes: classes) {
            for (index, line) in lines.enumerated()
            where NSLocationInRange(line.content.location, panel.range)
                || line.content.location == NSMaxRange(panel.range) {
                map[index] = panel.range
            }
        }
        return map
    }

    /// Collapses runs of code lines into single panels for background drawing.
    private static func codePanels(lines: [Line], classes: [LineClass]) -> [BlockDecoration] {
        var decorations: [BlockDecoration] = []
        var start: Int?

        func flush(end: Int) {
            guard let begin = start, end >= begin else { start = nil; return }
            let range = NSRange(
                location: lines[begin].enclosing.location,
                length: NSMaxRange(lines[end].content) - lines[begin].enclosing.location
            )
            decorations.append(BlockDecoration(kind: .codeBlock, range: range))
            start = nil
        }

        for index in lines.indices {
            let isCode = classes[index] == .code || classes[index] == .fenceMarker
            if isCode {
                if start == nil { start = index }
            } else if start != nil {
                flush(end: index - 1)
            }
        }
        if start != nil { flush(end: lines.count - 1) }

        return decorations
    }

    // MARK: - Body lines

    private static func styleBodyLine(
        _ storage: NSTextStorage,
        line: Line,
        typography: Typography,
        result: inout HighlightResult
    ) {
        let text = storage.string as NSString
        let raw = text.substring(with: line.content)
        let local = NSRange(location: 0, length: (raw as NSString).length)

        func absolute(_ range: NSRange) -> NSRange {
            NSRange(location: line.content.location + range.location, length: range.length)
        }

        func conceal(_ range: NSRange) {
            guard range.length > 0 else { return }
            result.conceals.append(ConcealRange(range: range, reveal: line.content))
        }

        // Headings — the hashes disappear, the size carries the level.
        if let match = heading.firstMatch(in: raw, range: local) {
            let level = match.range(at: 1).length
            storage.addAttributes(
                [.font: typography.heading(level), .foregroundColor: Palette.text],
                range: line.content
            )
            storage.addAttribute(
                .paragraphStyle,
                value: headingParagraphStyle(typography, level: level),
                range: line.enclosing
            )
            let prefix = absolute(
                NSRange(location: match.range(at: 1).location,
                        length: match.range(at: 1).length + match.range(at: 2).length)
            )
            storage.addAttributes([.foregroundColor: Palette.marker, .font: typography.body], range: prefix)
            conceal(prefix)
            styleInline(storage, in: absolute(match.range(at: 3)), reveal: line.content,
                        typography: typography, result: &result)
            return
        }

        // Blockquotes — the '>' becomes a bar in the margin.
        if let match = quote.firstMatch(in: raw, range: local) {
            storage.addAttribute(.paragraphStyle, value: quoteParagraphStyle(typography), range: line.enclosing)
            storage.addAttribute(.foregroundColor, value: Palette.secondary, range: line.content)
            let prefix = absolute(match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: Palette.marker, range: prefix)
            conceal(prefix)
            result.decorations.append(BlockDecoration(kind: .quote, range: line.enclosing))

            let rest = NSRange(
                location: NSMaxRange(prefix),
                length: NSMaxRange(line.content) - NSMaxRange(prefix)
            )
            if rest.length > 0 {
                styleInline(storage, in: rest, reveal: line.content, typography: typography, result: &result)
            }
            return
        }

        // Task list items — the '[ ]' becomes a drawn checkbox.
        if let match = task.firstMatch(in: raw, range: local) {
            let level = leadingLevel(match.range(at: 1).length)
            let indent = CGFloat(level) * typography.base * 1.1
            storage.addAttribute(
                .paragraphStyle,
                value: listParagraphStyle(typography, indent: indent, hanging: typography.base * 1.5),
                range: line.enclosing
            )
            let box = absolute(match.range(at: 2))
            let checked = text.substring(with: box).lowercased().contains("x")
            let prefix = NSRange(
                location: line.content.location,
                length: NSMaxRange(match.range(at: 3))
            )
            storage.addAttributes([.foregroundColor: Palette.marker, .font: typography.code], range: prefix)
            conceal(prefix)
            result.decorations.append(
                BlockDecoration(kind: .checkbox(indent: indent, checked: checked), range: line.enclosing)
            )

            let rest = NSRange(
                location: NSMaxRange(prefix),
                length: NSMaxRange(line.content) - NSMaxRange(prefix)
            )
            if rest.length > 0 {
                if checked {
                    storage.addAttributes(
                        [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                         .foregroundColor: Palette.secondary],
                        range: rest
                    )
                }
                styleInline(storage, in: rest, reveal: line.content, typography: typography, result: &result)
            }
            return
        }

        // Bullet lists — the '-' becomes a drawn dot.
        if let match = bulletList.firstMatch(in: raw, range: local) {
            let level = leadingLevel(match.range(at: 1).length)
            let indent = CGFloat(level) * typography.base * 1.1
            storage.addAttribute(
                .paragraphStyle,
                value: listParagraphStyle(typography, indent: indent, hanging: typography.base * 1.1),
                range: line.enclosing
            )
            let prefix = NSRange(location: line.content.location, length: NSMaxRange(match.range(at: 3)))
            storage.addAttribute(.foregroundColor, value: Palette.marker, range: prefix)
            conceal(prefix)
            result.decorations.append(
                BlockDecoration(kind: .bullet(indent: indent, level: level), range: line.enclosing)
            )

            let rest = NSRange(
                location: NSMaxRange(prefix),
                length: NSMaxRange(line.content) - NSMaxRange(prefix)
            )
            if rest.length > 0 {
                styleInline(storage, in: rest, reveal: line.content, typography: typography, result: &result)
            }
            return
        }

        // Ordered lists — the number is content, so it stays.
        if let match = orderedList.firstMatch(in: raw, range: local) {
            let level = leadingLevel(match.range(at: 1).length)
            let indent = CGFloat(level) * typography.base * 1.1
            storage.addAttribute(
                .paragraphStyle,
                value: listParagraphStyle(typography, indent: indent, hanging: typography.base * 1.6),
                range: line.enclosing
            )
            storage.addAttribute(.foregroundColor, value: Palette.secondary, range: absolute(match.range(at: 2)))

            let rest = NSRange(
                location: line.content.location + NSMaxRange(match.range(at: 3)),
                length: line.content.length - NSMaxRange(match.range(at: 3))
            )
            if rest.length > 0 {
                styleInline(storage, in: rest, reveal: line.content, typography: typography, result: &result)
            }
            return
        }

        styleInline(storage, in: line.content, reveal: line.content, typography: typography, result: &result)
    }

    /// Two spaces or one tab per nesting level, which covers both common styles.
    private static func leadingLevel(_ whitespaceLength: Int) -> Int {
        min(4, whitespaceLength / 2)
    }

    // MARK: - Inline spans

    private static func styleInline(
        _ storage: NSTextStorage,
        in range: NSRange,
        reveal: NSRange,
        typography: Typography,
        result: inout HighlightResult
    ) {
        guard range.length > 0 else { return }
        var protected = IndexSet()
        let string = storage.string
        var conceals: [ConcealRange] = []

        func overlaps(_ candidate: NSRange) -> Bool {
            candidate.length > 0
                && protected.intersects(integersIn: candidate.lowerBound..<candidate.upperBound)
        }

        func protect(_ candidate: NSRange) {
            guard candidate.length > 0 else { return }
            protected.insert(integersIn: candidate.lowerBound..<candidate.upperBound)
        }

        func hide(_ candidate: NSRange) {
            guard candidate.length > 0 else { return }
            storage.addAttribute(.foregroundColor, value: Palette.marker, range: candidate)
            conceals.append(ConcealRange(range: candidate, reveal: reveal))
        }

        func matches(_ expression: NSRegularExpression) -> [NSTextCheckingResult] {
            expression.matches(in: string, range: range)
        }

        // Code spans first: everything inside them is literal.
        for match in matches(codeSpan) where !overlaps(match.range) {
            storage.addAttributes(
                [.font: typography.code, .foregroundColor: Palette.codeText],
                range: match.range(at: 2)
            )
            hide(match.range(at: 1))
            hide(match.range(at: 3))
            protect(match.range)
        }

        for expression in [boldStar, boldUnderscore] {
            for match in matches(expression) where !overlaps(match.range) {
                addTrait(.boldFontMask, to: storage, range: match.range(at: 2))
                hide(match.range(at: 1))
                hide(match.range(at: 3))
                protect(match.range)
            }
        }

        for expression in [italicStar, italicUnderscore] {
            for match in matches(expression) where !overlaps(match.range) {
                addTrait(.italicFontMask, to: storage, range: match.range(at: 2))
                hide(match.range(at: 1))
                hide(match.range(at: 3))
                protect(match.range)
            }
        }

        for match in matches(strikethrough) where !overlaps(match.range) {
            storage.addAttributes(
                [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                 .foregroundColor: Palette.secondary],
                range: match.range(at: 2)
            )
            hide(match.range(at: 1))
            hide(match.range(at: 3))
            protect(match.range)
        }

        // Links keep their label and shed the brackets and URL.
        for match in matches(link) where !overlaps(match.range) {
            storage.addAttributes(
                [.foregroundColor: Palette.accent,
                 .underlineStyle: NSUnderlineStyle.single.rawValue,
                 .underlineColor: Palette.accentFaded],
                range: match.range(at: 2)
            )
            hide(match.range(at: 1))
            hide(match.range(at: 3))
            protect(match.range)
        }

        for match in matches(autolink) where !overlaps(match.range) {
            storage.addAttribute(.foregroundColor, value: Palette.accent, range: match.range(at: 2))
            hide(match.range(at: 1))
            hide(match.range(at: 3))
            protect(match.range)
        }

        for match in matches(bareURL) where !overlaps(match.range) {
            storage.addAttribute(.foregroundColor, value: Palette.accent, range: match.range)
            protect(match.range)
        }

        result.conceals.append(contentsOf: conceals)
    }

    private static func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, range: NSRange) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
    }
}
