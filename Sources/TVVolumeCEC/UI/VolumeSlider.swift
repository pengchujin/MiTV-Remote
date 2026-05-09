import AppKit

final class VolumeSlider: NSSlider {
    var onDrag: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onDrag?()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.onDrag?()
            return event
        } as Any
        super.mouseDown(with: event)
        NSEvent.removeMonitor(monitor)
    }
}
