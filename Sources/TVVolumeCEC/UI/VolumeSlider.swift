import AppKit

final class VolumeSlider: NSSlider {
    var onDrag: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onDrag?()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] e in
            self?.onDrag?()
            return e
        }
        super.mouseDown(with: event)
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
