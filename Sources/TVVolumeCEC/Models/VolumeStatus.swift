import Foundation

struct VolumeStatus {
    let volume: Int
    let maxVolume: Int

    var percent: Int {
        guard maxVolume > 0 else {
            return 0
        }
        return Int((Double(volume) / Double(maxVolume) * 100).rounded())
    }
}
