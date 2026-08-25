import Foundation

/// Branding-Gating für persönliche Kontakt-/Infrastruktur-Referenzen.
///
/// **Offizielle Builds** (unsere CI/Signierung, `make … OFFICIAL=1` →
/// `-DOFFICIAL_BUILD`) enthalten die persönliche Kontakt-E-Mail und die
/// Landing-Page-URLs. **Community-Builds** aus dem Repo (Standard, ohne Flag)
/// bleiben neutral: alle Werte sind `nil`, die zugehörigen UI-Elemente
/// (QR-Karte „Hol dir die iPhone-App", Mail-Button) werden ausgeblendet und
/// die Über-Seite zeigt stattdessen einen „Community build"-Hinweis.
///
/// Der GitHub-Repository-Link ist bewusst NICHT gegated (`HostLinks.repository`)
/// — Quellcode & Issues gelten für beide Varianten.
enum BrandingConfig {

    #if OFFICIAL_BUILD
    /// Kontakt-E-Mail (Über-Seite, „E-Mail senden").
    static let contactEmail: String? = "mail@tim-ehrenfried.de"
    /// Projekt-Landing-Page.
    static let landingPageURL: URL? = URL(string: "https://keystrokeqr.tim-ehrenfried.de")
    /// Weiterleitungs-URL zur iPhone-App (führt später zur App-Store-Seite).
    /// Wird als QR-Code im Onboarding/Kontrollpanel gerendert.
    static let iosAppURL: URL? = URL(string: "https://keystrokeqr.tim-ehrenfried.de/ios")
    #else
    static let contactEmail: String? = nil
    static let landingPageURL: URL? = nil
    static let iosAppURL: URL? = nil
    #endif

    /// `true` nur, wenn mit `-DOFFICIAL_BUILD` gebaut wurde.
    static var isOfficialBuild: Bool {
        #if OFFICIAL_BUILD
        return true
        #else
        return false
        #endif
    }
}
