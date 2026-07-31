import AppKit
import SwiftUI

/// Reports whether the pointer is inside its bounds without ever taking part in
/// hit testing. SwiftUI's `.onHover` needs a hit-testable shape, which would
/// steal clicks from the text view underneath; a tracking area does not.
struct HoverSentinel: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughTrackingView()
        view.onChange = { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PassThroughTrackingView)?.onChange = { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
    }

    private final class PassThroughTrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self
                )
            )
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}
