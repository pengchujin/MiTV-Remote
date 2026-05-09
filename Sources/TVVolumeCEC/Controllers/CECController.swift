import AppKit
import CECPrivateBridge

final class CECController {
    private let miTV = MiTVController()

    var currentHost: String {
        miTV.currentHost
    }

    func send(_ command: CECCommand) async -> CECResult {
        if let keyCode = command.miTVKeyCode {
            return await miTV.sendKey(keyCode)
        }
        return CECResult(isSuccess: false, message: L.string("status.no_cec_keycode"))
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

    func setVolumePercentImmediate(_ percent: Int) async -> CECResult {
        await miTV.setVolumePercentImmediate(percent)
    }

    func sendRemoteKey(_ key: String) async -> CECResult {
        await miTV.sendKey(key)
    }

    func switchHDMIInput(_ input: Int) async -> CECResult {
        await miTV.switchHDMIInput(input)
    }

    func discoverDevices() async -> Result<[MiTVDevice], CECResult> {
        await miTV.discoverDevices()
    }

    func setDeviceHost(_ host: String) {
        miTV.setHost(host)
    }

    func deviceStatus() async -> Result<MiTVDevice, CECResult> {
        await miTV.deviceStatus()
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
                return CECResult(isSuccess: false, message: L.string("cec.check_failed", name, result.message))
            }
            await sleepForCECStep()
        }

        for _ in 0..<100 {
            let result = await runPrivateCEC(0x02)
            guard result.isSuccess else {
                return CECResult(isSuccess: false, message: L.string("cec.down_reset_failed", result.message))
            }
            await sleepForCECStep()
        }

        for _ in 0..<clamped {
            let result = await runPrivateCEC(0x01)
            guard result.isSuccess else {
                return CECResult(isSuccess: false, message: L.string("cec.up_brightness_failed", result.message))
            }
            await sleepForCECStep()
        }

        for _ in 0..<2 {
            _ = await runPrivateCEC(0x0D)
            await sleepForCECStep()
        }

        return CECResult(isSuccess: true, message: L.string("cec.brightness_sequence_sent"))
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
            return L.string("cec.no_details")
        }
        let message = String(cString: pointer)
        TVCECPrivateFreeMessage(pointer)
        return message
    }
}
