import Foundation

/// Zentrale Branding-Konfiguration mit Compile-Time-Gating.
///
/// Offizielle Builds (von uns bzw. der CI signiert) enthalten persönliche
/// Kontakt- und Infrastruktur-Referenzen (E-Mail, Landing-Page, Mac-Host-
/// Download). Builds durch Dritte aus dem Public-Repo sollen NEUTRAL sein
/// und keine dieser Referenzen tragen.
///
/// Aktivierung ausschließlich von außen über die Compile-Condition
/// `OFFICIAL_BUILD` — im Projekt ist sie bewusst NICHT gesetzt:
///
///     xcodebuild … SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) OFFICIAL_BUILD'
///
/// Ein Standard-Build ohne Zusatz ist damit automatisch ein neutraler
/// Community-Build: alle optionalen Werte sind `nil`, die UI blendet die
/// entsprechenden Einträge aus und zeigt stattdessen einen Community-Hinweis.
/// Wichtig: Die Literale stehen INNERHALB der `#if`-Blöcke — in neutralen
/// Builds landen E-Mail/URLs also gar nicht erst im Binary (per
/// `strings`-Grep verifizierbar).
///
/// Der GitHub-Repo-Link ist absichtlich UNGATED — er verweist auf den
/// Quellcode selbst (MIT) und ist in jedem Build korrekt.
enum BrandingConfig {
    /// Kontakt-E-Mail für „Über“ — nur in offiziellen Builds, sonst `nil`.
    static let contactEmail: String? = {
        #if OFFICIAL_BUILD
        return "mail@tim-ehrenfried.de"
        #else
        return nil
        #endif
    }()

    /// Landing-Page des Projekts — nur in offiziellen Builds, sonst `nil`.
    static let landingPageURL: URL? = {
        #if OFFICIAL_BUILD
        return URL(string: "https://keystrokeqr.tim-ehrenfried.de")
        #else
        return nil
        #endif
    }()

    /// Download-Seite des aktuellen Mac-Hosts — nur in offiziellen Builds,
    /// sonst `nil`.
    static let macDownloadURL: URL? = {
        #if OFFICIAL_BUILD
        return URL(string: "https://keystrokeqr.tim-ehrenfried.de/mac")
        #else
        return nil
        #endif
    }()

    /// Quellcode-Repository (MIT) — bewusst in JEDEM Build vorhanden.
    static let repositoryURL = URL(string: "https://github.com/tim-ehrenfried/keystrokeqr")!

    /// True in offiziellen Builds (Flag `OFFICIAL_BUILD` gesetzt).
    static var isOfficialBuild: Bool {
        #if OFFICIAL_BUILD
        return true
        #else
        return false
        #endif
    }
}
