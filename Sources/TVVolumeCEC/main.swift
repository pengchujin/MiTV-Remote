import AppKit

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var volumeLabel: NSTextField?
    private var volumeSlider: NSSlider?
    private var deviceIPLabel: NSTextField?
    private var deviceNameLabel: NSTextField?
    private var brightnessLabel: NSTextField?
    private var brightnessPercent = 50
    private var keyEventMonitors: [Any] = []
    private weak var remoteControlView: RemoteControlView?
    private let cec = CECController()
    private let brightness = BrightnessController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }) {
            keyEventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            _ = self?.handleKeyDown(event)
        }) {
            keyEventMonitors.append(monitor)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = remoteStatusIcon()
            button.image?.isTemplate = true
            button.toolTip = "MiTV Remote"
        }
        item.menu = makeMenu()
        updateStatusUI(deviceName: nil)
        refreshVolume()
        refreshBrightness()
        refreshDeviceStatus()
    }

    // MARK: - Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: L.string("menu.tv_volume"), action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let controls = NSMenuItem()
        controls.view = makeControlsView()
        menu.addItem(controls)
        menu.addItem(.separator())
        menu.addItem(menuItem(L.string("menu.search_device"), symbol: "magnifyingglass", key: "s", action: #selector(searchAndSwitchDevice)))
        menu.addItem(menuItem(L.string("menu.quit"), symbol: "power", key: "q", action: #selector(quit)))
        return menu
    }

    private func remoteStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()
        let body = NSBezierPath(roundedRect: NSRect(x: 5, y: 2, width: 8, height: 14), xRadius: 3, yRadius: 3)
        body.lineWidth = 1.6
        body.stroke()
        NSBezierPath(ovalIn: NSRect(x: 7.2, y: 11, width: 3.6, height: 3.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 7.7, y: 7.2, width: 2.6, height: 2.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 7.7, y: 4.2, width: 2.6, height: 2.6)).fill()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Controls View

    private func makeControlsView() -> NSView {
        let view = RemoteControlView(frame: NSRect(x: 0, y: 0, width: 240, height: 326))
        view.onKeyDown = { [weak self] event in self?.handleKeyDown(event) ?? event }
        remoteControlView = view

        let label = NSTextField(labelWithString: L.string("status.volume_placeholder"))
        label.frame = NSRect(x: 16, y: 298, width: 208, height: 18)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        view.addSubview(label)
        volumeLabel = label

        let slider = VolumeSlider(value: 50, minValue: 0, maxValue: 100, target: self, action: #selector(volumeSliderChanged(_:)))
        slider.frame = NSRect(x: 12, y: 268, width: 216, height: 28)
        slider.isContinuous = false
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false
        slider.onDrag = { [weak self] in
            let percent = Int(slider.doubleValue.rounded())
            self?.updateVolumeUI(percent)
        }
        view.addSubview(slider)
        volumeSlider = slider

        addRemoteButton(to: view, title: "HDMI 1", frame: NSRect(x: 18, y: 228, width: 94, height: 30), action: #selector(switchHDMI1), label: L.string("tooltip.hdmi1"))
        addRemoteButton(to: view, title: "HDMI 2", frame: NSRect(x: 128, y: 228, width: 94, height: 30), action: #selector(switchHDMI2), label: L.string("tooltip.hdmi2"))
        addRemoteButton(to: view, symbol: "power", frame: NSRect(x: 18, y: 190, width: 44, height: 32), action: #selector(remotePower), label: L.string("tooltip.power"))
        addRemoteButton(to: view, symbol: "speaker.minus.fill", frame: NSRect(x: 98, y: 190, width: 44, height: 32), action: #selector(remoteVolumeDown), label: L.string("tooltip.volume_down"))
        addRemoteButton(to: view, symbol: "speaker.plus.fill", frame: NSRect(x: 178, y: 190, width: 44, height: 32), action: #selector(remoteVolumeUp), label: L.string("tooltip.volume_up"))

        addRemoteButton(to: view, symbol: "chevron.up", frame: NSRect(x: 102, y: 158, width: 36, height: 28), action: #selector(remoteUp), label: L.string("tooltip.up"))
        addRemoteButton(to: view, symbol: "chevron.left", frame: NSRect(x: 54, y: 122, width: 36, height: 28), action: #selector(remoteLeft), label: L.string("tooltip.left"))
        addRemoteButton(to: view, title: "OK", frame: NSRect(x: 100, y: 118, width: 40, height: 36), action: #selector(remoteOK), label: L.string("tooltip.confirm"))
        addRemoteButton(to: view, symbol: "chevron.right", frame: NSRect(x: 150, y: 122, width: 36, height: 28), action: #selector(remoteRight), label: L.string("tooltip.right"))
        addRemoteButton(to: view, symbol: "chevron.down", frame: NSRect(x: 102, y: 84, width: 36, height: 28), action: #selector(remoteDown), label: L.string("tooltip.down"))

        addRemoteButton(to: view, symbol: "house", frame: NSRect(x: 18, y: 54, width: 44, height: 30), action: #selector(remoteHome), label: L.string("tooltip.home"))
        addRemoteButton(to: view, symbol: "arrow.uturn.backward", frame: NSRect(x: 88, y: 54, width: 64, height: 30), action: #selector(remoteBack), label: L.string("tooltip.back"))
        addRemoteButton(to: view, symbol: "line.3.horizontal", frame: NSRect(x: 178, y: 54, width: 44, height: 30), action: #selector(remoteMenu), label: L.string("tooltip.menu"))

        deviceIPLabel = addStatusLabel(to: view, frame: NSRect(x: 14, y: 32, width: 212, height: 14))
        deviceNameLabel = addStatusLabel(to: view, frame: NSRect(x: 14, y: 17, width: 212, height: 14))
        return view
    }

    @discardableResult
    private func addStatusLabel(to view: NSView, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.frame = frame
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        view.addSubview(label)
        return label
    }

    private func addRemoteButton(to view: NSView, symbol: String, frame: NSRect, action: Selector, label: String) {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: self, action: action)
        button.frame = frame
        button.bezelStyle = .rounded
        button.toolTip = label
        view.addSubview(button)
    }

    private func addRemoteButton(to view: NSView, title: String, frame: NSRect, action: Selector, label: String) {
        let button = NSButton(title: title, target: self, action: action)
        button.frame = frame
        button.bezelStyle = .rounded
        button.toolTip = label
        view.addSubview(button)
    }

    private func menuItem(_ title: String, symbol: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let key: String?
        switch event.keyCode {
        case 123: key = "left"
        case 124: key = "right"
        case 125: key = "down"
        case 126: key = "up"
        case 36:  key = "enter"     // Return → OK
        case 76:  key = "enter"     // Enter (numpad) → OK
        case 51:  key = "back"      // Delete → Back
        default:  key = nil
        }
        guard let key else { return event }
        sendRemoteKey(key)
        return nil
    }

    // MARK: - Actions

    @objc private func volumeUp() { run(.volumeUp) }
    @objc private func volumeDown() { run(.volumeDown) }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let target = Int(sender.doubleValue.rounded())
        setVolumePercent(target)
    }

    @objc private func brightnessUp() { adjustBrightness(.up) }
    @objc private func brightnessDown() { adjustBrightness(.down) }

    @objc private func checkConnection() {
        Task {
            let result = await cec.checkAvailability()
            await MainActor.run {
                showResult(title: result.isSuccess ? L.string("alert.connected") : L.string("alert.connection_failed"), result: result)
            }
        }
    }

    @objc private func searchAndSwitchDevice() {
        Task {
            let result = await cec.discoverDevices()
            await MainActor.run {
                switch result {
                case .success(let devices): presentDevicePicker(devices)
                case .failure(let failure): showResult(title: L.string("alert.search_failed"), result: failure)
                }
            }
        }
    }

    @objc private func becomeActiveSource() {
        Task {
            let result = await cec.becomeActiveSource()
            await MainActor.run {
                showResult(title: result.isSuccess ? L.string("alert.active_source_sent") : L.string("alert.active_source_failed"), result: result)
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func remotePower() { sendRemoteKey("power") }
    @objc private func remoteVolumeDown() { sendRemoteKey("volumedown") }
    @objc private func remoteVolumeUp() { sendRemoteKey("volumeup") }
    @objc private func remoteUp() { sendRemoteKey("up") }
    @objc private func remoteDown() { sendRemoteKey("down") }
    @objc private func remoteLeft() { sendRemoteKey("left") }
    @objc private func remoteRight() { sendRemoteKey("right") }
    @objc private func remoteOK() { sendRemoteKey("enter") }
    @objc private func remoteHome() { sendRemoteKey("home") }
    @objc private func remoteBack() { sendRemoteKey("back") }
    @objc private func remoteMenu() { sendRemoteKey("menu") }
    @objc private func switchHDMI1() { switchHDMIInput(1) }
    @objc private func switchHDMI2() { switchHDMIInput(2) }

    // MARK: - Remote Commands

    private func run(_ command: CECCommand) {
        Task {
            let result = await cec.send(command)
            await MainActor.run {
                if !result.isSuccess { showResult(title: L.string("alert.cec_failed"), result: result) }
                else { refreshVolume() }
            }
        }
    }

    private func sendRemoteKey(_ key: String) {
        Task {
            let result = await cec.sendRemoteKey(key)
            await MainActor.run {
                if !result.isSuccess { showResult(title: L.string("alert.remote_failed"), result: result) }
                else if key == "volumeup" || key == "volumedown" { refreshVolume() }
            }
        }
    }

    private func switchHDMIInput(_ input: Int) {
        Task {
            let result = await cec.switchHDMIInput(input)
            await MainActor.run {
                if !result.isSuccess { showResult(title: L.string("alert.hdmi_failed"), result: result) }
            }
        }
    }

    // MARK: - Refresh

    private func refreshDeviceStatus() {
        Task {
            let status = await cec.deviceStatus()
            await MainActor.run {
                switch status {
                case .success(let device): updateStatusUI(deviceName: device.name)
                case .failure: updateStatusUI(deviceName: nil)
                }
            }
        }
    }

    private func refreshVolume() {
        Task {
            let status = await cec.volumeStatus()
            await MainActor.run {
                switch status {
                case .success(let volume): updateVolumeUI(volume.percent)
                case .failure: volumeLabel?.stringValue = L.string("status.volume_placeholder")
                }
            }
        }
    }

    private func refreshBrightness() {
        Task {
            let status = await brightness.brightnessStatus()
            await MainActor.run {
                switch status {
                case .success(let percent): updateBrightnessUI(percent)
                case .failure: brightnessLabel?.stringValue = L.string("status.brightness_placeholder")
                }
            }
        }
    }

    private func setVolumePercent(_ percent: Int) {
        updateVolumeUI(percent)
        Task {
            let result = await cec.setVolumePercentImmediate(percent)
            await MainActor.run {
                if !result.isSuccess { showResult(title: L.string("alert.volume_failed"), result: result) }
                refreshVolume()
            }
        }
    }

    private func adjustBrightness(_ direction: BrightnessDirection) {
        let nextPercent = brightnessPercent + direction.percentDelta
        updateBrightnessUI(nextPercent)
        Task {
            let result = await brightness.adjustBrightness(direction)
            await MainActor.run {
                if !result.isSuccess {
                    showResult(title: L.string("alert.brightness_failed"), result: result)
                    refreshBrightness()
                }
            }
        }
    }

    private func updateVolumeUI(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        volumeLabel?.stringValue = L.string("status.volume", "\(clamped)%")
        volumeSlider?.integerValue = clamped
    }

    private func updateBrightnessUI(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        brightnessPercent = clamped
        brightnessLabel?.stringValue = L.string("status.brightness", "\(clamped)%")
    }

    private func updateStatusUI(deviceName: String?) {
        let host = cec.currentHost
        let name = deviceName ?? UserDefaults.standard.string(forKey: "MiTVDeviceName")
        deviceIPLabel?.stringValue = L.string("status.device_ip", host)
        deviceNameLabel?.stringValue = L.string("status.device_name", name?.isEmpty == false ? name! : "--")
    }

    private func showResult(title: String, result: CECResult) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = result.message
        alert.alertStyle = result.isSuccess ? .informational : .warning
        alert.addButton(withTitle: L.string("alert.ok"))
        alert.runModal()
    }

    private func presentDevicePicker(_ devices: [MiTVDevice]) {
        guard !devices.isEmpty else {
            showResult(title: L.string("picker.no_device"), result: CECResult(isSuccess: false, message: L.string("picker.no_device_message")))
            return
        }
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28), pullsDown: false)
        for device in devices {
            let item = NSMenuItem(title: "\(device.name)  \(device.host)", action: nil, keyEquivalent: "")
            item.representedObject = device.host
            popup.menu?.addItem(item)
        }
        let alert = NSAlert()
        alert.messageText = L.string("picker.select_device")
        alert.informativeText = L.string("picker.found_devices", "\(devices.count)")
        alert.accessoryView = popup
        alert.addButton(withTitle: L.string("picker.use"))
        alert.addButton(withTitle: L.string("picker.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, let host = popup.selectedItem?.representedObject as? String else { return }
        cec.setDeviceHost(host)
        if let device = devices.first(where: { $0.host == host }) {
            UserDefaults.standard.set(device.name, forKey: "MiTVDeviceName")
        }
        refreshVolume()
        refreshDeviceStatus()
        showResult(title: L.string("picker.switched"), result: CECResult(isSuccess: true, message: L.string("picker.current_target", host)))
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
