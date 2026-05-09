import AppKit
import CryptoKit
import Darwin

final class MiTVController {
    private let port = 6095
    private var backlightOSDActiveUntil: Date?
    private var cachedSystemInfo: MiTVSystemInfo?
    private var cachedMaxVolume: Int?

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

    var currentHost: String { host }

    var currentInputName: String {
        UserDefaults.standard.string(forKey: "MiTVInputName") ?? "--"
    }

    func setHost(_ host: String) {
        UserDefaults.standard.set(host, forKey: "MiTVHost")
        cachedSystemInfo = nil
        cachedMaxVolume = nil
    }

    func setCurrentInputName(_ inputName: String) {
        UserDefaults.standard.set(inputName, forKey: "MiTVInputName")
    }

    func checkAvailability() async -> CECResult {
        await request(path: "/controller?action=getinstalledapp&count=1", successMessage: L.string("status.connected", "\(host):\(port)"))
    }

    func deviceStatus() async -> Result<MiTVDevice, CECResult> {
        let result = await requestJSON(path: "/request?action=isalive")
        guard result.response.isSuccess,
              let root = result.json as? [String: Any],
              let data = root["data"] as? [String: Any]
        else {
            return .failure(result.response)
        }
        let name = (data["devicename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(MiTVDevice(name: name?.isEmpty == false ? name! : "MiTV", host: host))
    }

    func discoverDevices() async -> Result<[MiTVDevice], CECResult> {
        let prefixes = Self.localIPv4Prefixes()
        guard !prefixes.isEmpty else {
            return .failure(CECResult(isSuccess: false, message: L.string("status.no_lan_ip")))
        }
        let hosts = Set(prefixes.flatMap { prefix in (1...254).map { "\(prefix).\($0)" } })
        let devices = await withTaskGroup(of: MiTVDevice?.self, returning: [MiTVDevice].self) { group in
            for host in hosts {
                group.addTask { await self.probeDevice(host) }
            }
            var found: [MiTVDevice] = []
            for await device in group {
                if let device { found.append(device) }
            }
            return found.sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
        }
        return .success(devices)
    }

    private func probeDevice(_ host: String) async -> MiTVDevice? {
        let result = await requestJSON(host: host, path: "/request?action=isalive", timeout: 0.45)
        guard result.response.isSuccess,
              let root = result.json as? [String: Any],
              let data = root["data"] as? [String: Any]
        else { return nil }
        let name = (data["devicename"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MiTVDevice(name: name?.isEmpty == false ? name! : "MiTV", host: host)
    }

    func volumeStatus() async -> Result<VolumeStatus, CECResult> {
        let result = await requestJSON(path: "/controller?action=getvolume")
        guard result.response.isSuccess else { return .failure(result.response) }
        guard let root = result.json as? [String: Any],
              let data = root["data"] as? [String: Any],
              let volume = data["volume"] as? Int,
              let maxVolume = data["maxVolume"] as? Int
        else {
            return .failure(CECResult(isSuccess: false, message: L.string("status.no_volume_format", result.body)))
        }
        cachedMaxVolume = maxVolume
        return .success(VolumeStatus(volume: volume, maxVolume: maxVolume))
    }

    func systemInfo() async -> Result<MiTVSystemInfo, CECResult> {
        let result = await requestJSON(path: "/controller?action=getsysteminfo")
        guard result.response.isSuccess else { return .failure(result.response) }
        guard let root = result.json as? [String: Any],
              let data = root["data"] as? [String: Any]
        else {
            return .failure(CECResult(isSuccess: false, message: L.string("status.no_systeminfo_format", result.body)))
        }
        let info = MiTVSystemInfo(wifiMAC: data["wifimac"] as? String, ethernetMAC: data["ethmac"] as? String)
        cachedSystemInfo = info
        return .success(info)
    }

    func setVolumePercent(_ percent: Int) async -> CECResult {
        let clamped = min(100, max(0, percent))
        let statusResult = await volumeStatus()
        guard case .success(let status) = statusResult else {
            if case .failure(let failure) = statusResult { return failure }
            return CECResult(isSuccess: false, message: L.string("status.cannot_read_volume"))
        }
        let targetVolume = Int((Double(clamped) / 100.0 * Double(status.maxVolume)).rounded())
        let signedResult = await setVolumeBySignedGeneralAPI(targetVolume)
        if signedResult.isSuccess { return signedResult }
        let delta = targetVolume - status.volume
        guard delta != 0 else {
            return CECResult(isSuccess: true, message: L.string("status.volume_already", "\(clamped)%"))
        }
        let keyCode = delta > 0 ? "volumeup" : "volumedown"
        for _ in 0..<abs(delta) {
            let result = await sendKey(keyCode)
            if !result.isSuccess { return result }
            try? await Task.sleep(nanoseconds: 45_000_000)
        }
        return CECResult(isSuccess: true, message: L.string("status.fallback_used", "\(clamped)%", signedResult.message))
    }

    func setVolumePercentImmediate(_ percent: Int) async -> CECResult {
        let clamped = min(100, max(0, percent))

        if let info = cachedSystemInfo, let mac = info.signingMAC {
            let targetVolume = cachedMaxVolume.map { Int((Double(clamped) / 100.0 * Double($0)).rounded()) } ?? clamped
            let result = await setVolumeBySignedGeneralAPICached(targetVolume, mac: mac)
            if result.isSuccess { return result }
        }

        return await setVolumePercent(clamped)
    }

    private func setVolumeBySignedGeneralAPICached(_ volume: Int, mac: String) async -> CECResult {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signSource = "mitvsignsalt&\(volume)&\(mac)&\(timestamp)"
        let sign = Self.md5(signSource)
        let path = "/general?action=setVolum&volum=\(volume)&ts=\(timestamp)&sign=\(sign)"
        let result = await requestJSON(path: path)
        guard result.response.isSuccess else {
            return CECResult(isSuccess: false, message: L.string("status.signed_api_unavailable", path, result.response.message))
        }
        return CECResult(isSuccess: true, message: L.string("status.signed_volume_set", "\(volume)"))
    }

    private func setVolumeBySignedGeneralAPI(_ volume: Int) async -> CECResult {
        let systemInfoResult = await systemInfo()
        guard case .success(let info) = systemInfoResult, let mac = info.signingMAC else {
            if case .failure(let failure) = systemInfoResult { return failure }
            return CECResult(isSuccess: false, message: L.string("status.no_mac"))
        }
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let signSource = "mitvsignsalt&\(volume)&\(mac)&\(timestamp)"
        let sign = Self.md5(signSource)
        let path = "/general?action=setVolum&volum=\(volume)&ts=\(timestamp)&sign=\(sign)"
        let result = await requestJSON(path: path)
        guard result.response.isSuccess else {
            return CECResult(isSuccess: false, message: L.string("status.signed_api_unavailable", path, result.response.message))
        }
        return CECResult(isSuccess: true, message: L.string("status.signed_volume_set", "\(volume)"))
    }

    private static func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func sendKey(_ keyCode: String) async -> CECResult {
        await request(path: "/controller?action=keyevent&keycode=\(keyCode)", successMessage: L.string("status.key_sent", keyCode))
    }

    func switchHDMIInput(_ input: Int) async -> CECResult {
        let clamped = min(2, max(1, input))
        return await switchInputSource("hdmi\(clamped)", displayName: "HDMI \(clamped)")
    }

    func switchInputSource(_ source: String, displayName: String) async -> CECResult {
        return await request(path: "/controller?action=changesource&source=\(source)", successMessage: L.string("status.source_switched", displayName))
    }

    func adjustBacklight(_ direction: BrightnessDirection) async -> CECResult {
        let shouldOpenBacklightMenu = !(backlightOSDActiveUntil.map { Date() < $0 } ?? false)
        if shouldOpenBacklightMenu {
            for key in ["menu", "right", "down", "right"] {
                let result = await sendKey(key)
                guard result.isSuccess else { return result }
                await sleepForMenuStep()
            }
        }
        let result = await sendKey(direction.remoteKey)
        guard result.isSuccess else { return result }
        backlightOSDActiveUntil = Date().addingTimeInterval(10)
        return CECResult(isSuccess: true, message: shouldOpenBacklightMenu
            ? L.string("brightness.opened_menu", direction.displayName)
            : L.string("brightness.osd_still_open", direction.displayName))
    }

    private func sleepForMenuStep() async { try? await Task.sleep(nanoseconds: 400_000_000) }
    private func sleepForAdjustmentStep() async { try? await Task.sleep(nanoseconds: 35_000_000) }

    private func request(path: String, successMessage: String) async -> CECResult {
        let result = await requestJSON(path: path)
        guard result.response.isSuccess else { return result.response }
        return CECResult(isSuccess: true, message: "\(successMessage)\n\n\(result.body)")
    }

    private func requestJSON(path: String) async -> (response: CECResult, json: Any?, body: String) {
        await requestJSON(host: host, path: path, timeout: 2)
    }

    private func requestJSON(host: String, path: String, timeout: TimeInterval) async -> (response: CECResult, json: Any?, body: String) {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            return (CECResult(isSuccess: false, message: L.string("status.invalid_address", host)), nil, "")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        do {
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            let normalizedBody = body.replacingOccurrences(of: "\r", with: "")
            let json = try? JSONSerialization.jsonObject(with: data)
            guard statusCode == 200 else {
                return (CECResult(isSuccess: false, message: "HTTP \(statusCode)\n\(normalizedBody)"), json, normalizedBody)
            }
            if normalizedBody.localizedCaseInsensitiveContains("\"msg\":\"success\"") {
                return (CECResult(isSuccess: true, message: normalizedBody), json, normalizedBody)
            }
            return (CECResult(isSuccess: false, message: normalizedBody.isEmpty ? L.string("status.no_response") : normalizedBody), json, normalizedBody)
        } catch {
            return (CECResult(isSuccess: false, message: L.string("status.cannot_connect", host, "\(port)", error.localizedDescription)), nil, "")
        }
    }

    private static func localIPv4Prefixes() -> [String] {
        var addresses: [String] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }
        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var addr = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: buffer)
            let parts = ip.split(separator: ".")
            guard parts.count == 4 else { continue }
            addresses.append(parts.prefix(3).joined(separator: "."))
        }
        return Array(Set(addresses)).sorted()
    }
}
