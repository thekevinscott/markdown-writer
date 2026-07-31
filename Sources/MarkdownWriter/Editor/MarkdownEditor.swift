import AppKit
import SwiftUI

/// Bridges the AppKit editor into SwiftUI. Deliberately thin: all the styling
/// lives in `MarkdownHighlighter`, all the layout in `WritingTextView`.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var typography: Typography

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 explicitly: the decoration drawing below relies on
        // NSLayoutManager geometry, which TextKit 2 doesn't expose the same way.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = WritingTextView(frame: .zero, textContainer: container)
        // The text view is its own layout manager delegate: that is the hook
        // that suppresses glyphs for concealed syntax.
        layoutManager.delegate = textView
        textView.typography = typography
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.backgroundColor = Palette.background
        textView.drawsBackground = true
        textView.insertionPointColor = Palette.insertionPoint
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Markdown is punctuation-sensitive. Curly quotes and em-dash
        // substitution corrupt source text, so every substitution is off.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        let coordinator = context.coordinator
        textView.delegate = coordinator
        textView.string = text
        textView.onAppearanceChange = { [weak textView, weak coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.rehighlight(textView)
        }

        storage.delegate = coordinator
        coordinator.textView = textView
        coordinator.rehighlight(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.background
        scrollView.borderType = .noBorder
        // Let content scroll clear of the traffic lights and the status bar.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? WritingTextView else { return }
        context.coordinator.text = $text

        if textView.string != text {
            // External change (undo through the document, revert, etc.).
            let selection = textView.selectedRange()
            textView.string = text
            let clamped = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
            textView.setSelectedRange(clamped)
            context.coordinator.rehighlight(textView)
        }

        if textView.typography != typography {
            textView.typography = typography
            context.coordinator.rehighlight(textView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var text: Binding<String>
        weak var textView: WritingTextView?
        private var highlightScheduled = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            scheduleHighlight()
        }

        /// Re-entrancy guard: mutating attributes from inside `didProcessEditing`
        /// re-enters the storage, so the work is deferred one runloop turn and
        /// coalesced across bursts of typing.
        private func scheduleHighlight() {
            guard !highlightScheduled else { return }
            highlightScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.highlightScheduled = false
                if let textView = self.textView { self.rehighlight(textView) }
            }
        }

        func rehighlight(_ textView: WritingTextView) {
            guard let storage = textView.textStorage else { return }
            let result = MarkdownHighlighter.apply(to: storage, typography: textView.typography)
            textView.decorations = result.decorations
            textView.conceals = result.conceals
            textView.syncTypingAttributes()
        }
    }
}
