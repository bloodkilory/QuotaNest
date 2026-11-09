import Foundation

enum DisplaySource: Equatable {
    case official(QuotaProviderID)
    case api(String)
    case harness
}

/// One persisted selection drives both the capsule and its detail view.
final class DisplaySelection {
    private let defaults: UserDefaults
    private(set) var source: DisplaySource
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.bool(forKey:"selectedHarness") { source = .harness }
        else if let id = defaults.string(forKey:"pinnedCCSwitchConnection") { source = .api(id) }
        else { source = .official(QuotaProviderID(rawValue:defaults.string(forKey:"selectedProvider") ?? "") ?? .codex) }
    }
    func select(_ value: DisplaySource) {
        source = value
        defaults.set(value == .harness,forKey:"selectedHarness")
        switch value {
        case .official(let provider):
            defaults.set(provider.rawValue,forKey:"selectedProvider")
            defaults.removeObject(forKey:"pinnedCCSwitchConnection")
        case .api(let id): defaults.set(id,forKey:"pinnedCCSwitchConnection")
        case .harness: defaults.removeObject(forKey:"pinnedCCSwitchConnection")
        }
    }
    var provider: QuotaProviderID {
        if case .official(let provider) = source { return provider }
        return QuotaProviderID(rawValue:defaults.string(forKey:"selectedProvider") ?? "") ?? .codex
    }
    var accountID: String? { if case .api(let id) = source { return id }; return nil }
    func model(for provider: QuotaProviderID) -> String? { defaults.string(forKey:"quotaModel." + provider.rawValue) }
    func selectModel(_ id: String?, for provider: QuotaProviderID) {
        let key = "quotaModel." + provider.rawValue
        if let id { defaults.set(id,forKey:key) } else { defaults.removeObject(forKey:key) }
    }
}
