import Foundation
import ServiceManagement

/// Kapselt „Beim Login starten" über `SMAppService.mainApp` (macOS 13+).
///
/// Hinweis: `SMAppService` wirkt nur zuverlässig aus einer **installierten,
/// signierten .app** heraus (z. B. in `/Applications`). Aus einem nackten
/// SPM-Binary ohne Bundle liefert die API u. U. `notFound`/Fehler — die Logik
/// ist trotzdem vorhanden und liest/serialisiert den Status korrekt, damit sie
/// in der ausgelieferten App voll funktioniert.
enum LoginItemManager {

    /// Vereinfachter, UI-tauglicher Status.
    enum Status: Equatable {
        /// Als Login-Item registriert und aktiv.
        case enabled
        /// Nicht registriert (Standard).
        case notRegistered
        /// Registriert, aber vom Nutzer in den Systemeinstellungen noch nicht
        /// freigegeben (macOS „Anmeldeobjekte").
        case requiresApproval
        /// API meldet, dass kein passendes Item gefunden wurde (i. d. R. nur beim
        /// Start aus einem nicht installierten Bundle).
        case notFound
    }

    /// Aktueller Registrierungsstatus (ohne Seiteneffekte).
    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled:           return .enabled
        case .notRegistered:     return .notRegistered
        case .requiresApproval:  return .requiresApproval
        case .notFound:          return .notFound
        @unknown default:        return .notRegistered
        }
    }

    /// `true`, wenn der Autostart aktiv ist.
    static var isEnabled: Bool { status == .enabled }

    /// Registriert die App als Login-Item. Wirft den zugrunde liegenden Fehler,
    /// damit die UI eine freundliche Meldung zeigen kann.
    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    /// Deregistriert die App als Login-Item.
    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }

    /// Schaltet den Autostart auf `desired`. Gibt bei Erfolg `nil`, sonst den
    /// Fehler zurück (nicht werfend — bequem für Schalter-Callbacks).
    static func setEnabled(_ desired: Bool) -> Error? {
        do {
            if desired { try enable() } else { try disable() }
            return nil
        } catch {
            return error
        }
    }
}
