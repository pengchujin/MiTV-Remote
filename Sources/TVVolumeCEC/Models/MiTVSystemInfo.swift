import Foundation

struct MiTVSystemInfo {
    let wifiMAC: String?
    let ethernetMAC: String?

    var signingMAC: String? {
        (ethernetMAC ?? wifiMAC)?
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
    }
}
