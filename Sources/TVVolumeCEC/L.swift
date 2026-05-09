import Foundation

enum L {
    private static let preferredLanguage: String = {
        let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        if preferred.hasPrefix("en") { return "en" }
        return "zh-Hans"
    }()

    private static let bundle: Bundle = {
        let mainBundle = Bundle.main
        if let path = mainBundle.path(forResource: preferredLanguage, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = mainBundle.path(forResource: "zh-Hans", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return mainBundle
    }()

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, arguments: args)
    }
}
