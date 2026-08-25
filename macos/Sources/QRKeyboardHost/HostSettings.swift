import Foundation

/// Zentrale, persistente Nutzereinstellungen des Hosts (UserDefaults).
/// Keine UI — nur die Schlüssel und typisierte Zugriffe.
enum HostSettings {
    /// Wurde das Erst-Start-Onboarding schon einmal gezeigt?
    static let didCompleteOnboardingKey = "didCompleteHostOnboarding"

    static var didCompleteOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: didCompleteOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: didCompleteOnboardingKey) }
    }
}

/// Einstellbare Tippgeschwindigkeit (siehe `KeyInjector`). Steuert die
/// Chunk-Größe und die Pause zwischen den Unicode-Chunks: „Langsam“ tippt in
/// kleineren Häppchen mit deutlich größeren Pausen, damit sich bei viel Text
/// oder trägen/entfernten Zielfeldern nichts „verfängt“; „Schnell“ tippt zügig.
/// Persistiert in UserDefaults; im Menü mit Häkchen markiert.
enum TypingSpeed: String, CaseIterable {
    case fast
    case normal
    case slow

    static let defaultsKey = "typingSpeed"

    /// Aktuell gewählte Geschwindigkeit (Default: `.normal` — entspricht dem
    /// bisherigen festen Verhalten). Thread-agnostisch über UserDefaults.
    static var current: TypingSpeed {
        get { TypingSpeed(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Chunk-Größe in UTF-16-Einheiten für `keyboardSetUnicodeString`.
    var chunkSize: Int {
        switch self {
        case .fast:   return 40
        case .normal: return 20   // bisheriger Wert
        case .slow:   return 8
        }
    }

    /// Pause zwischen zwei Chunks in Mikrosekunden.
    var interChunkDelayMicroseconds: useconds_t {
        switch self {
        case .fast:   return 3_000
        case .normal: return 10_000  // bisheriger Wert
        case .slow:   return 32_000
        }
    }

    /// Lokalisierter Menütitel (`menu.typingSpeed.fast|normal|slow`).
    var localizedTitle: String {
        L("menu.typingSpeed.\(rawValue)")
    }
}
