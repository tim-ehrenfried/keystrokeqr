import Foundation

/// Kurzschreibweise für `NSLocalizedString` (Tabelle `Localizable`, `Bundle.main`).
///
/// Die Übersetzungen liegen als `en.lproj/Localizable.strings` (Basissprache,
/// Development Language) und `de.lproj/Localizable.strings` im App-Bundle unter
/// `Contents/Resources/` (siehe `macos/Support/*.lproj` + Makefile-Target `app`).
/// Basissprache/Development Region ist Englisch (`en`); Deutsch (`de`) ist die
/// zusätzliche, inhaltlich gleichwertige Lokalisierung — vgl. docs/BRANDING.md.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
