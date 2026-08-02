import AppKit

/// Selection-wrapping helpers for the frontmost editor. Menu commands can't
/// reach into a specific `NSTextView` through SwiftUI, so they go through the
/// first responder — the same route AppKit's own text commands take.
enum MarkdownFormatter {

    private static var focusedTextView: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    /// Wraps the selection in `marker`, or unwraps it if it's already wrapped.
    /// With an empty selection it inserts the pair and parks the caret inside.
    static func wrap(_ marker: String) {
        guard let textView = focusedTextView else { return }
        let string = textView.string as NSString
        let selection = textView.selectedRange()
        let markerLength = (marker as NSString).length

        let outer = NSRange(
            location: selection.location - markerLength,
            length: selection.length + markerLength * 2
        )
        let isWrapped = outer.location >= 0
            && NSMaxRange(outer) <= string.length
            && string.substring(with: outer).hasPrefix(marker)
            && string.substring(with: outer).hasSuffix(marker)

        if isWrapped {
            let inner = string.substring(with: selection)
            guard textView.shouldChangeText(in: outer, replacementString: inner) else { return }
            textView.textStorage?.replaceCharacters(in: outer, with: inner)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: outer.location, length: selection.length))
        } else {
            let selected = string.substring(with: selection)
            let replacement = marker + selected + marker
            guard textView.shouldChangeText(in: selection, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: selection, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(
                NSRange(location: selection.location + markerLength, length: selection.length)
            )
        }
    }

    /// `[selection](url)` — caret lands in the URL slot, which is what you want
    /// next 90% of the time.
    static func link() {
        guard let textView = focusedTextView else { return }
        let string = textView.string as NSString
        let selection = textView.selectedRange()
        let label = string.substring(with: selection)
        let replacement = "[\(label)]()"

        guard textView.shouldChangeText(in: selection, replacementString: replacement) else { return }
        textView.textStorage?.replaceCharacters(in: selection, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(
            NSRange(location: selection.location + (replacement as NSString).length - 1, length: 0)
        )
    }

    static var hasFocusedEditor: Bool { focusedTextView != nil }
}
