import AppKit
import SwiftUI

/// The whole window: text, and a status bar that stays out of the way until
/// you go looking for it.
struct EditorView: View {
    @Binding var document: MarkdownDocument
    @ObservedObject private var preferences = Preferences.shared

    @State private var showsStatusBar = false
    @State private var windowTitle = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: Palette.background)
                .ignoresSafeArea()

            MarkdownEditor(text: $document.text, fontSize: preferences.fontSize)
                .ignoresSafeArea()

            statusBar
        }
        .background(WindowConfigurator(title: $windowTitle))
        .frame(minWidth: 480, minHeight: 400)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        ZStack(alignment: .bottom) {
            // Pass-through hover target. It never swallows clicks, so tapping
            // near the bottom of the document still moves the caret.
            HoverSentinel(isHovering: $showsStatusBar)
                .frame(height: 84)

            HStack(spacing: 12) {
                Text(windowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 24)

                Text(statistics)
                    .monospacedDigit()

                AppearanceToggle(mode: $preferences.appearance)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(nsColor: Palette.secondary))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .opacity(showsStatusBar ? 1 : 0)
            .allowsHitTesting(showsStatusBar)
            .animation(.easeInOut(duration: 0.18), value: showsStatusBar)
        }
    }

    private var statistics: String {
        let words = document.text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        let characters = document.text.count
        return "\(words) words · \(characters) characters"
    }
}

/// Three-way appearance switch: Auto / Light / Dark.
struct AppearanceToggle: View {
    @Binding var mode: AppearanceMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppearanceMode.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { mode = option }
                } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 20)
                        .background {
                            if mode == option {
                                Capsule()
                                    .fill(Color(nsColor: Palette.quoteBar))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .foregroundStyle(
                            Color(nsColor: mode == option ? Palette.text : Palette.secondary)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option.label)
                .accessibilityLabel(option.label)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(nsColor: Palette.codeBackground)))
    }
}

/// Applies the window chrome that SwiftUI's window modifiers don't reach, and
/// reports the document title back so the status bar can show it.
private struct WindowConfigurator: NSViewRepresentable {
    @Binding var title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Palette.background
        // One window per file, always — no tab merging.
        window.tabbingMode = .disallowed

        let name = window.representedURL?.deletingPathExtension().lastPathComponent ?? window.title
        if title != name { title = name }
    }
}
