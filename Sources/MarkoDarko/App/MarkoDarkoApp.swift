import AppKit
import SwiftUI

@main
struct MarkoDarkoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var preferences = Preferences.shared

    var body: some Scene {
        // One scene, one document, one window. There is nothing else to show.
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            EditorView(document: file.$document)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 820, height: 940)
        .commands { EditorCommands(preferences: preferences) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tabs would put two documents in one window; the whole premise is that
        // a file gets a window to itself.
        NSWindow.allowsAutomaticWindowTabbing = false
        Preferences.shared.applyAppearance()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

struct EditorCommands: Commands {
    @ObservedObject var preferences: Preferences

    var body: some Commands {
        // Nothing here needs a toolbar or a sidebar.
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .help) {}

        CommandMenu("Format") {
            Button("Bold") { MarkdownFormatter.wrap("**") }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { MarkdownFormatter.wrap("_") }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { MarkdownFormatter.wrap("~~") }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Code") { MarkdownFormatter.wrap("`") }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Link") { MarkdownFormatter.link() }
                .keyboardShortcut("k", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Picker("Appearance", selection: $preferences.appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Divider()
            // Numbered shortcuts so you can flip between faces quickly and
            // judge them against the same paragraph.
            Menu("Typeface") {
                ForEach(Array(EditorFont.allCases.enumerated()), id: \.element.id) { index, font in
                    Button(font.label) { preferences.fontFamily = font }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(index + 1)")),
                            modifiers: [.command, .option]
                        )
                }
            }
            Divider()
            Button("Bigger Text") { preferences.nudgeFontSize(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { preferences.nudgeFontSize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { preferences.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }
    }
}
