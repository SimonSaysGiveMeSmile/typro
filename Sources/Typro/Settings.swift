import Foundation
import AppKit

final class TyproSettings {
    static let shared = TyproSettings()

    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?

    private enum Keys {
        static let enabled = "typro.enabled"
        static let minWordLength = "typro.minWordLength"
        static let allowlistMode = "typro.allowlistMode"
        static let bundleIDs = "typro.bundleIDs"
        static let language = "typro.language"
        static let predictionsEnabled = "typro.predictionsEnabled"
        static let capitalizeI = "typro.capitalizeI"
        static let sentenceCapEnabled = "typro.sentenceCap"
    }

    enum AllowlistMode: String {
        case everywhere
        case onlyListed
        case exceptListed
    }

    func bootstrap() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.minWordLength: 3,
            Keys.allowlistMode: AllowlistMode.everywhere.rawValue,
            Keys.bundleIDs: [String](),
            Keys.language: "en",
            Keys.predictionsEnabled: true,
            Keys.capitalizeI: true,
            Keys.sentenceCapEnabled: true,
        ])
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Keys.enabled) }
        set { defaults.set(newValue, forKey: Keys.enabled); onChange?() }
    }

    var minWordLength: Int {
        get { max(2, defaults.integer(forKey: Keys.minWordLength)) }
        set { defaults.set(newValue, forKey: Keys.minWordLength); onChange?() }
    }

    var allowlistMode: AllowlistMode {
        get { AllowlistMode(rawValue: defaults.string(forKey: Keys.allowlistMode) ?? "") ?? .everywhere }
        set { defaults.set(newValue.rawValue, forKey: Keys.allowlistMode); onChange?() }
    }

    var bundleIDs: [String] {
        get { defaults.stringArray(forKey: Keys.bundleIDs) ?? [] }
        set { defaults.set(newValue, forKey: Keys.bundleIDs); onChange?() }
    }

    var language: String {
        get { defaults.string(forKey: Keys.language) ?? "en" }
        set { defaults.set(newValue, forKey: Keys.language); onChange?() }
    }

    var predictionsEnabled: Bool {
        get { defaults.bool(forKey: Keys.predictionsEnabled) }
        set { defaults.set(newValue, forKey: Keys.predictionsEnabled); onChange?() }
    }

    var capitalizeI: Bool {
        get { defaults.bool(forKey: Keys.capitalizeI) }
        set { defaults.set(newValue, forKey: Keys.capitalizeI); onChange?() }
    }

    var sentenceCapEnabled: Bool {
        get { defaults.bool(forKey: Keys.sentenceCapEnabled) }
        set { defaults.set(newValue, forKey: Keys.sentenceCapEnabled); onChange?() }
    }

    func shouldActivate(forBundleID id: String?) -> Bool {
        guard enabled else { return false }
        switch allowlistMode {
        case .everywhere: return true
        case .onlyListed: return id.map { bundleIDs.contains($0) } ?? false
        case .exceptListed: return !(id.map { bundleIDs.contains($0) } ?? false)
        }
    }
}
