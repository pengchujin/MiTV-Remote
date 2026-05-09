import Foundation

enum CECCommand {
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
