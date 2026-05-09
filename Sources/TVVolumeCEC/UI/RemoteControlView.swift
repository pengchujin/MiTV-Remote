import AppKit

final class RemoteControlView: NSView {
    var onKeyDown: ((NSEvent) -> NSEvent?)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if let forwarded = onKeyDown?(event) {
            super.keyDown(with: forwarded)
        }
    }
}
