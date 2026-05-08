import AppKit
import CECPrivateBridge
import CryptoKit

private final class RemoteControlView: NSView {
    var onKeyDown: ((NSEvent) -> NSEvent?)?

    override var acceptsFirstResponder: Bool {
        true
    }

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

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var volumeLabel: NSTextField?
    private var volumeSlider: NSSlider?
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
            button.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "TV Volume")
            button.image?.isTemplate = true
            button.toolTip = "TV Volume over HDMI-CEC"
        }

        item.menu = makeMenu()
        refreshVolume()
        refreshBrightness()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let title = NSMenuItem(title: "电视音量", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let controls = NSMenuItem()
        controls.view = makeControlsView()
        menu.addItem(controls)
        menu.addItem(.separator())

        menu.addItem(menuItem("检查小米电视 Wi-Fi", symbol: "wifi", key: "c", action: #selector(checkConnection)))
        menu.addItem(menuItem("退出", symbol: "power", key: "q", action: #selector(quit)))

        return menu
    }

    private func makeControlsView() -> NSView {
        let view = RemoteControlView(frame: NSRect(x: 0, y: 0, width: 240, height: 272))
        view.onKeyDown = { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
        remoteControlView = view

        let label = NSTextField(labelWithString: "当前音量：--%")
        label.frame = NSRect(x: 16, y: 244, width: 208, height: 18)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        view.addSubview(label)
        volumeLabel = label

        let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: self, action: #selector(volumeSliderChanged(_:)))
        slider.frame = NSRect(x: 12, y: 214, width: 216, height: 28)
        slider.isContinuous = false
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false
        view.addSubview(slider)
        volumeSlider = slider

        addRemoteButton(to: view, title: "HDMI 1", frame: NSRect(x: 18, y: 174, width: 94, height: 30), action: #selector(switchHDMI1), label: "切换 HDMI 1")
        addRemoteButton(to: view, title: "HDMI 2", frame: NSRect(x: 128, y: 174, width: 94, height: 30), action: #selector(switchHDMI2), label: "切换 HDMI 2")
        addRemoteButton(to: view, symbol: "power", frame: NSRect(x: 18, y: 136, width: 44, height: 32), action: #selector(remotePower), label: "电源")
        addRemoteButton(to: view, symbol: "speaker.minus.fill", frame: NSRect(x: 98, y: 136, width: 44, height: 32), action: #selector(remoteVolumeDown), label: "音量减")
        addRemoteButton(to: view, symbol: "speaker.plus.fill", frame: NSRect(x: 178, y: 136, width: 44, height: 32), action: #selector(remoteVolumeUp), label: "音量加")

        addRemoteButton(to: view, symbol: "chevron.up", frame: NSRect(x: 102, y: 104, width: 36, height: 28), action: #selector(remoteUp), label: "上")
        addRemoteButton(to: view, symbol: "chevron.left", frame: NSRect(x: 54, y: 68, width: 36, height: 28), action: #selector(remoteLeft), label: "左")
        addRemoteButton(to: view, title: "OK", frame: NSRect(x: 100, y: 64, width: 40, height: 36), action: #selector(remoteOK), label: "确认")
        addRemoteButton(to: view, symbol: "chevron.right", frame: NSRect(x: 150, y: 68, width: 36, height: 28), action: #selector(remoteRight), label: "右")
        addRemoteButton(to: view, symbol: "chevron.down", frame: NSRect(x: 102, y: 30, width: 36, height: 28), action: #selector(remoteDown), label: "下")

        addRemoteButton(to: view, symbol: "house", frame: NSRect(x: 18, y: 0, width: 44, height: 30), action: #selector(remoteHome), label: "主页")
        addRemoteButton(to: view, symbol: "arrow.uturn.backward", frame: NSRect(x: 88, y: 0, width: 64, height: 30), action: #selector(remoteBack), label: "返回")
        addRemoteButton(to: view, symbol: "line.3.horizontal", frame: NSRect(x: 178, y: 0, width: 44, height: 30), action: #selector(remoteMenu), label: "菜单")

        return view
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

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let key: String?
        switch event.keyCode {
        case 123:
            key = "left"
        case 124:
            key = "right"
        case 125:
            key = "down"
        case 126:
            key = "up"
        default:
            key = nil
        }

        guard let key else {
            return event
        }

        sendRemoteKey(key)
        return nil
    }

    @objc private func volumeUp() {
        run(.volumeUp)
    }

    @objc private func volumeDown() {
        run(.volumeDown)
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let target = Int(sender.doubleValue.rounded())
        setVolumePercent(target)
    }

    @objc private func brightnessUp() {
        adjustBrightness(.up)
    }

    @objc private func brightnessDown() {
        adjustBrightness(.down)
    }

    @objc private func checkConnection() {
        Task {
            let result = await cec.checkAvailability()
            await MainActor.run {
                showResult(title: result.isSuccess ? "小米电视已连接" : "小米电视连接失败", result: result)
            }
        }
    }

    @objc private func becomeActiveSource() {
        Task {
            let result = await cec.becomeActiveSource()
            await MainActor.run {
                showResult(title: result.isSuccess ? "已发送信号源命令" : "信号源命令失败", result: result)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func remotePower() {
        sendRemoteKey("power")
    }

    @objc private func remoteVolumeDown() {
        sendRemoteKey("volumedown")
    }

    @objc private func remoteVolumeUp() {
        sendRemoteKey("volumeup")
    }

    @objc private func remoteUp() {
        sendRemoteKey("up")
    }

    @objc private func remoteDown() {
        sendRemoteKey("down")
    }

    @objc private func remoteLeft() {
        sendRemoteKey("left")
    }

    @objc private func remoteRight() {
        sendRemoteKey("right")
    }

    @objc private func remoteOK() {
        sendRemoteKey("enter")
    }

    @objc private func remoteHome() {
        sendRemoteKey("home")
    }

    @objc private func remoteBack() {
        sendRemoteKey("back")
    }

    @objc private func remoteMenu() {
        sendRemoteKey("menu")
    }

    @objc private func switchHDMI1() {
        switchHDMIInput(1)
    }

    @objc private func switchHDMI2() {
        switchHDMIInput(2)
    }

    private func run(_ command: CECCommand) {
        Task {
            let result = await cec.send(command)
            await MainActor.run {
                if !result.isSuccess {
                    showResult(title: "CEC Command Failed", result: result)
                } else {
                    refreshVolume()
                }
            }
        }
    }

    private func sendRemoteKey(_ key: String) {
        Task {
            let result = await cec.sendRemoteKey(key)
            await MainActor.run {
                if !result.isSuccess {
                    showResult(title: "遥控器命令失败", result: result)
                } else if key == "volumeup" || key == "volumedown" {
                    refreshVolume()
                }
            }
        }
    }

    private func switchHDMIInput(_ input: Int) {
        Task {
            let result = await cec.switchHDMIInput(input)
            await MainActor.run {
                if !result.isSuccess {
                    showResult(title: "HDMI 切换失败", result: result)
                }
            }
        }
    }

    private func refreshVolume() {
        Task {
            let status = await cec.volumeStatus()
            await MainActor.run {
                switch status {
                case .success(let volume):
                    updateVolumeUI(volume.percent)
                case .failure:
                    volumeLabel?.stringValue = "当前音量：--%"
                }
            }
        }
    }

    private func refreshBrightness() {
        Task {
            let status = await brightness.brightnessStatus()
            await MainActor.run {
                switch status {
                case .success(let percent):
                    updateBrightnessUI(percent)
                case .failure:
                    brightnessLabel?.stringValue = "当前亮度：--%"
                }
            }
        }
    }

    private func setVolumePercent(_ percent: Int) {
        updateVolumeUI(percent)
        Task {
            let result = await cec.setVolumePercent(percent)
            await MainActor.run {
                if !result.isSuccess {
                    showResult(title: "设置音量失败", result: result)
                }
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
                    showResult(title: "设置亮度失败", result: result)
                    refreshBrightness()
                }
            }
        }
    }

    private func updateVolumeUI(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        volumeLabel?.stringValue = "当前音量：\(clamped)%"
        volumeSlider?.integerValue = clamped
    }

    private func updateBrightnessUI(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        brightnessPercent = clamped
        brightnessLabel?.stringValue = "当前亮度：\(clamped)%"
    }

    private func showResult(title: String, result: CECResult) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = result.message
        alert.alertStyle = result.isSuccess ? .informational : .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private enum CECCommand {
    case volumeUp
    case volumeDown

    var miTVKeyCode: String? {
        switch self {
        case .volumeUp:
            return "volumeup"
        case .volumeDown:
            return "volumedown"
        }
    }

    var userControlCode: UInt8 {
        switch self {
        case .volumeUp:
            return 0x41
        case .volumeDown:
            return 0x42
        }
    }
}

private struct CECResult: Error {
    let isSuccess: Bool
    let message: String
}

private struct VolumeStatus {
    let volume: Int
    let maxVolume: Int

    var percent: Int {
        guard maxVolume > 0 else {
            return 0
        }
        return Int((Double(volume) / Double(maxVolume) * 100).rounded())
    }
}

private struct MiTVSystemInfo {
    let wifiMAC: String?
    let ethernetMAC: String?

    var signingMAC: String? {
        (ethernetMAC ?? wifiMAC)?
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
    }
}

private enum BrightnessDirection {
    case up
    case down

    var remoteKey: String {
        switch self {
        case .up:
            return "up"
        case .down:
            return "down"
        }
    }

    var percentDelta: Int {
        switch self {
        case .up:
            return 1
        case .down:
            return -1
        }
    }

    var displayName: String {
        switch self {
        case .up:
            return "提高"
        case .down:
            return "降低"
        }
    }
}

private final class CECController {
    private let miTV = MiTVController()

    func send(_ command: CECCommand) async -> CECResult {
        if let keyCode = command.miTVKeyCode {
            return await miTV.sendKey(keyCode)
        }

        return CECResult(isSuccess: false, message: "小米电视 6095 接口没有发现可用的静音 keycode。音量增大/减小已走 Wi-Fi 接口。")
    }

    func checkAvailability() async -> CECResult {
        await miTV.checkAvailability()
    }

    func becomeActiveSource() async -> CECResult {
        await miTV.sendKey("menu")
    }

    func volumeStatus() async -> Result<VolumeStatus, CECResult> {
        await miTV.volumeStatus()
    }

    func setVolumePercent(_ percent: Int) async -> CECResult {
        await miTV.setVolumePercent(percent)
    }

    func setVolumePercentViaSetVolumOnly(_ percent: Int) async -> CECResult {
        await miTV.setVolumePercentViaSetVolumOnly(percent)
    }

    func sendRemoteKey(_ key: String) async -> CECResult {
        await miTV.sendKey(key)
    }

    func switchHDMIInput(_ input: Int) async -> CECResult {
        await miTV.switchHDMIInput(input)
    }

    func setBrightnessPercentViaCECMenu(_ percent: Int) async -> CECResult {
        let clamped = min(100, max(0, percent))
        let openBrightness: [(UInt8, String)] = [
            (0x09, "菜单"),
            (0x04, "右键"),
            (0x02, "下键"),
            (0x00, "确认")
        ]

        for (code, name) in openBrightness {
            let result = await runPrivateCEC(code)
            guard result.isSuccess else {
                return CECResult(isSuccess: false, message: "CEC \(name) 失败。\n\n\(result.message)")
            }
            await sleepForCECStep()
        }

        for _ in 0..<100 {
            let result = await runPrivateCEC(0x02)
            guard result.isSuccess else {
                return CECResult(isSuccess: false, message: "CEC 下键归零失败。\n\n\(result.message)")
            }
            await sleepForCECStep()
        }

        for _ in 0..<clamped {
            let result = await runPrivateCEC(0x01)
            guard result.isSuccess else {
                return CECResult(isSuccess: false, message: "CEC 上键调亮失败。\n\n\(result.message)")
            }
            await sleepForCECStep()
        }

        for _ in 0..<2 {
            _ = await runPrivateCEC(0x0D)
            await sleepForCECStep()
        }

        return CECResult(
            isSuccess: true,
            message: "已通过 Apple 私有 IOCEC 发送 CEC 菜单亮度序列：菜单、右键、下键、确认、上下键。"
        )
    }

    func becomeActiveSourceViaCEC() async -> CECResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var messagePointer: UnsafeMutablePointer<CChar>?
                let ok = TVCECPrivateCheck(&messagePointer)
                continuation.resume(returning: CECResult(isSuccess: ok, message: Self.message(from: messagePointer)))
            }
        }
    }

    private func runPrivateCEC(_ command: UInt8) async -> CECResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var messagePointer: UnsafeMutablePointer<CChar>?
                let ok = TVCECPrivateSendUserControl(command, &messagePointer)
                continuation.resume(returning: CECResult(isSuccess: ok, message: Self.message(from: messagePointer)))
            }
        }
    }

    private func runPrivateActiveSourceCEC() async -> CECResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var messagePointer: UnsafeMutablePointer<CChar>?
                let ok = TVCECPrivateBecomeActiveSource(&messagePointer)
                continuation.resume(returning: CECResult(isSuccess: ok, message: Self.message(from: messagePointer)))
            }
        }
    }

    private func sleepForCECStep() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    private static func message(from pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else {
            return "Apple 私有 IOCEC 没有返回详细信息。"
        }

        let message = String(cString: pointer)
        TVCECPrivateFreeMessage(pointer)
        return message
    }
}

private final class MiTVController {
    private let port = 6095
    private var backlightOSDActiveUntil: Date?

    private var host: String {
        if let value = ProcessInfo.processInfo.environment["TV_VOLUME_MITV_HOST"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        if let value = UserDefaults.standard.string(forKey: "MiTVHost")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        return "192.168.1.50"
    }

    func checkAvailability() async -> CECResult {
        await request(path: "/controller?action=getinstalledapp&count=1", successMessage: "已连接到小米电视：\(host):\(port)")
    }

    func volumeStatus() async -> Result<VolumeStatus, CECResult> {
        let result = await requestJSON(path: "/controller?action=getvolume")
        guard result.response.isSuccess else {
            return .failure(result.response)
        }

        guard
            let root = result.json as? [String: Any],
            let data = root["data"] as? [String: Any],
            let volume = data["volume"] as? Int,
            let maxVolume = data["maxVolume"] as? Int
        else {
            return .failure(CECResult(isSuccess: false, message: "小米电视返回的音量格式无法识别。\n\n\(result.body)"))
        }

        return .success(VolumeStatus(volume: volume, maxVolume: maxVolume))
    }

    func systemInfo() async -> Result<MiTVSystemInfo, CECResult> {
        let result = await requestJSON(path: "/controller?action=getsysteminfo")
        guard result.response.isSuccess else {
            return .failure(result.response)
        }

        guard
            let root = result.json as? [String: Any],
            let data = root["data"] as? [String: Any]
        else {
            return .failure(CECResult(isSuccess: false, message: "小米电视返回的系统信息格式无法识别。\n\n\(result.body)"))
        }

        return .success(MiTVSystemInfo(
            wifiMAC: data["wifimac"] as? String,
            ethernetMAC: data["ethmac"] as? String
        ))
    }

    func setVolumePercent(_ percent: Int) async -> CECResult {
        let clamped = min(100, max(0, percent))

        let statusResult = await volumeStatus()
        guard case .success(let status) = statusResult else {
            if case .failure(let failure) = statusResult {
                return failure
            }
            return CECResult(isSuccess: false, message: "无法读取当前音量。")
        }

        let targetVolume = Int((Double(clamped) / 100.0 * Double(status.maxVolume)).rounded())
        let signedResult = await setVolumeBySignedGeneralAPI(targetVolume)
        if signedResult.isSuccess {
            return signedResult
        }

        let delta = targetVolume - status.volume
        guard delta != 0 else {
            return CECResult(isSuccess: true, message: "音量已经是 \(clamped)%。")
        }

        let keyCode = delta > 0 ? "volumeup" : "volumedown"
        for _ in 0..<abs(delta) {
            let result = await sendKey(keyCode)
            if !result.isSuccess {
                return result
            }
            try? await Task.sleep(nanoseconds: 45_000_000)
        }

        return CECResult(isSuccess: true, message: "签名音量接口不可用，已用遥控按键设置到约 \(clamped)%。\n\n\(signedResult.message)")
    }

    func setVolumePercentViaSetVolumOnly(_ percent: Int) async -> CECResult {
        let clamped = min(100, max(0, percent))
        let statusResult = await volumeStatus()
        let targetVolume: Int

        if case .success(let status) = statusResult {
            targetVolume = Int((Double(clamped) / 100.0 * Double(status.maxVolume)).rounded())
        } else {
            targetVolume = clamped
        }

        return await setVolumeBySignedGeneralAPI(targetVolume)
    }

    private func setVolumeBySignedGeneralAPI(_ volume: Int) async -> CECResult {
        let systemInfoResult = await systemInfo()
        guard case .success(let info) = systemInfoResult, let mac = info.signingMAC else {
            if case .failure(let failure) = systemInfoResult {
                return failure
            }
            return CECResult(isSuccess: false, message: "无法读取小米设备 MAC，不能生成 setVolum 签名。")
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signSource = "mitvsignsalt&\(volume)&\(mac)&\(timestamp)"
        let sign = Self.md5(signSource)
        let path = "/general?action=setVolum&volum=\(volume)&ts=\(timestamp)&sign=\(sign)"
        let result = await requestJSON(path: path)
        guard result.response.isSuccess else {
            return CECResult(
                isSuccess: false,
                message: """
                文章里的 setVolum 签名接口在当前设备上不可用，已回退到遥控按键方式。

                请求路径：\(path)
                返回：\(result.response.message)
                """
            )
        }

        return CECResult(isSuccess: true, message: "已通过 setVolum 签名接口设置音量：\(volume)。")
    }

    private static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func sendKey(_ keyCode: String) async -> CECResult {
        await request(path: "/controller?action=keyevent&keycode=\(keyCode)", successMessage: "已通过小米电视 Wi-Fi 接口发送：\(keyCode)")
    }

    func switchHDMIInput(_ input: Int) async -> CECResult {
        let clamped = min(2, max(1, input))
        return await switchInputSource("hdmi\(clamped)", displayName: "HDMI \(clamped)")
    }

    func switchInputSource(_ source: String, displayName: String) async -> CECResult {
        return await request(
            path: "/controller?action=changesource&source=\(source)",
            successMessage: "已通过小米电视 Wi-Fi 接口切换到 \(displayName)"
        )
    }

    func adjustBacklight(_ direction: BrightnessDirection) async -> CECResult {
        let shouldOpenBacklightMenu = !(backlightOSDActiveUntil.map { Date() < $0 } ?? false)

        if shouldOpenBacklightMenu {
            let openBacklight = ["menu", "right", "down", "right"]

            for key in openBacklight {
                let result = await sendKey(key)
                guard result.isSuccess else {
                    return result
                }
                await sleepForMenuStep()
            }
        }

        let result = await sendKey(direction.remoteKey)
        guard result.isSuccess else {
            return result
        }

        backlightOSDActiveUntil = Date().addingTimeInterval(10)

        return CECResult(
            isSuccess: true,
            message: shouldOpenBacklightMenu
                ? "已打开小米/Redmi 显示器亮度菜单并\(direction.displayName)亮度。OSD 菜单会在约 10 秒后自动消失。"
                : "OSD 菜单仍打开，只发送了\(direction.displayName)亮度按键。"
        )
    }

    private func sleepForMenuStep() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    private func sleepForAdjustmentStep() async {
        try? await Task.sleep(nanoseconds: 35_000_000)
    }

    private func request(path: String, successMessage: String) async -> CECResult {
        let result = await requestJSON(path: path)
        guard result.response.isSuccess else {
            return result.response
        }
        return CECResult(isSuccess: true, message: "\(successMessage)\n\n\(result.body)")
    }

    private func requestJSON(path: String) async -> (response: CECResult, json: Any?, body: String) {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            let response = CECResult(isSuccess: false, message: "小米电视地址无效：\(host)")
            return (response, nil, "")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            let normalizedBody = body.replacingOccurrences(of: "\r", with: "")
            let json = try? JSONSerialization.jsonObject(with: data)

            guard statusCode == 200 else {
                let response = CECResult(isSuccess: false, message: "HTTP \(statusCode)\n\(normalizedBody)")
                return (response, json, normalizedBody)
            }

            if normalizedBody.localizedCaseInsensitiveContains("\"msg\":\"success\"") {
                let response = CECResult(isSuccess: true, message: normalizedBody)
                return (response, json, normalizedBody)
            }

            let response = CECResult(isSuccess: false, message: normalizedBody.isEmpty ? "小米电视没有返回内容。" : normalizedBody)
            return (response, json, normalizedBody)
        } catch {
            let response = CECResult(
                isSuccess: false,
                message: """
                无法连接小米电视 Wi-Fi 接口：\(host):\(port)

                目前默认使用本机发现到的 mitv-mffu1 地址 192.168.1.50。
                如果电视 IP 变了，可以用环境变量指定：
                TV_VOLUME_MITV_HOST=电视IP ./script/build_and_run.sh

                \(error.localizedDescription)
                """
            )
            return (response, nil, "")
        }
    }
}

private final class BrightnessController {
    private let miTV = MiTVController()

    private enum Tool {
        case m1ddc(URL)
        case ddcctl(URL)

        var name: String {
            switch self {
            case .m1ddc:
                return "m1ddc"
            case .ddcctl:
                return "ddcctl"
            }
        }
    }

    func brightnessStatus() async -> Result<Int, CECResult> {
        guard let tool = findTool() else {
            return .success(50)
        }

        switch tool {
        case .m1ddc(let url):
            let result = await run(url, ["get", "luminance"])
            guard result.isSuccess else {
                return .failure(result)
            }
            guard let value = parsePercent(from: result.message, keywords: ["luminance", "brightness"]) else {
                return .failure(CECResult(isSuccess: false, message: "已找到 m1ddc，但没有读到当前亮度。\n\n\(result.message)"))
            }
            return .success(value)

        case .ddcctl(let url):
            let result = await run(url, ["-d", "1"])
            guard result.isSuccess else {
                return .failure(result)
            }
            guard let value = parsePercent(from: result.message, keywords: ["brightness", "luminance"]) else {
                return .failure(CECResult(isSuccess: false, message: "已找到 ddcctl，但没有读到当前亮度。\n\n\(result.message)"))
            }
            return .success(value)
        }
    }

    func adjustBrightness(_ direction: BrightnessDirection) async -> CECResult {
        await miTV.adjustBacklight(direction)
    }

    private func findTool() -> Tool? {
        if let url = findExecutable(named: "m1ddc") {
            return .m1ddc(url)
        }

        if let url = findExecutable(named: "ddcctl") {
            return .ddcctl(url)
        }

        return nil
    }

    private func findExecutable(named name: String) -> URL? {
        let fileManager = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let searchPaths = pathValue
            .split(separator: ":")
            .map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

        for directory in searchPaths {
            let path = "\(directory)/\(name)"
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }

    private func run(_ executableURL: URL, _ arguments: [String]) async -> CECResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: CECResult(isSuccess: true, message: output))
                    } else {
                        continuation.resume(returning: CECResult(
                            isSuccess: false,
                            message: "\(executableURL.lastPathComponent) 执行失败。\n\n\(output)"
                        ))
                    }
                } catch {
                    continuation.resume(returning: CECResult(
                        isSuccess: false,
                        message: "\(executableURL.lastPathComponent) 无法启动：\(error.localizedDescription)"
                    ))
                }
            }
        }
    }

    private func parsePercent(from output: String, keywords: [String]) -> Int? {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        let candidateLines = lines.filter { line in
            keywords.contains { keyword in
                line.localizedCaseInsensitiveContains(keyword)
            }
        } + lines

        for line in candidateLines {
            let numbers = line.split { !$0.isNumber }.compactMap { Int($0) }
            if let value = numbers.first(where: { (0...100).contains($0) }) {
                return value
            }
        }

        return nil
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
