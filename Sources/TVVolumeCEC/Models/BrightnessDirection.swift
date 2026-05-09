import Foundation

enum BrightnessDirection {
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
            return L.string("brightness.increase")
        case .down:
            return L.string("brightness.decrease")
        }
    }
}
