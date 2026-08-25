import Foundation
import CryptoKit
import Security

/// Nonce-Richtungspräfixe für verschlüsselte Frames (siehe docs/PROTOCOL-v2.md,
/// Abschnitt „Verschlüsselte Frames“). MÜSSEN mit `ios/QRKeyboardScanner/CryptoManager.swift`
/// identisch sein — sonst schlägt ChaChaPoly.open auf der Gegenseite fehl.
enum FrameDirection {
    /// Client → Host.
    static let clientToHost: [UInt8] = [0x71, 0x6B, 0x63, 0x31] // "qkc1"
    /// Host → Client.
    static let hostToClient: [UInt8] = [0x71, 0x6B, 0x68, 0x31] // "qkh1"
}

/// Verschlüsselt/entschlüsselt Nutz-Frames gemäß docs/PROTOCOL-v2.md.
///
/// Abweichung von der wörtlichen Spec-Formulierung „ChaChaPoly combined
/// (nonce implizit via seq)“: `ChaChaPoly.SealedBox.combined` in CryptoKit
/// enthält IMMER auch den 12-Byte-Nonce-Präfix — das widerspräche „nonce
/// implizit via seq“ (der Sinn des Felds `seq` ist ja gerade, den Nonce NICHT
/// zu übertragen). Deshalb wird hier bewusst `ciphertext‖tag` (ohne Nonce)
/// über die Leitung geschickt; der Nonce wird auf beiden Seiten deterministisch
/// aus Richtungspräfix + big-endian `seq` rekonstruiert. PROTOCOL-v2.md wurde
/// entsprechend präzisiert.
enum SecureFrame {
    enum FrameError: Error {
        case tooShort
    }

    static func nonce(prefix: [UInt8], seq: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = prefix
        withUnsafeBytes(of: seq.bigEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: bytes)
    }

    /// `plaintext` → `ciphertext‖tag` (16-Byte-Tag am Ende, kein Nonce-Präfix).
    static func seal(_ plaintext: Data, key: SymmetricKey, prefix: [UInt8], seq: UInt64) throws -> Data {
        let n = try nonce(prefix: prefix, seq: seq)
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: n)
        return sealed.ciphertext + sealed.tag
    }

    /// `ciphertext‖tag` → Klartext. Wirft bei Authentifizierungsfehler oder
    /// zu kurzer Eingabe.
    static func open(_ combined: Data, key: SymmetricKey, prefix: [UInt8], seq: UInt64) throws -> Data {
        guard combined.count >= 16 else { throw FrameError.tooShort }
        let n = try nonce(prefix: prefix, seq: seq)
        let tag = combined.suffix(16)
        let ciphertext = combined.prefix(combined.count - 16)
        let sealedBox = try ChaChaPoly.SealedBox(nonce: n, ciphertext: ciphertext, tag: tag)
        return try ChaChaPoly.open(sealedBox, using: key)
    }
}

private extension SymmetricKey {
    var dataRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}

/// Persistente Identität + gekoppelte Geräte in der Keychain
/// (Service `de.timehrenfried.keystrokeqr.host`), gemäß docs/PROTOCOL-v2.md.
/// Hinweis: reiner String-Wechsel beim Rebrand v0.7.0 — Items unter dem alten
/// Service (`de.timehrenfried.qr-keyboard-host`) werden NICHT migriert; Nutzer
/// koppeln einmalig neu (siehe docs/BRANDING.md).
/// Threadsicher (NSLock) — wird sowohl vom `ScanServer` (eigene Queue) als
/// auch von AppKit-UI (Main Thread: Menü, Pairing-Fenster) genutzt.
final class CryptoManager: @unchecked Sendable {

    static let keychainService = "de.timehrenfried.keystrokeqr.host"
    private static let accountIdentity = "identity"
    private static let accountPairedDevices = "paired-devices"

    struct PairedDevice: Codable, Identifiable {
        var id: UUID { deviceID }
        let deviceID: UUID
        var name: String
        let clientPublicKey: Data
        let psk: Data
        let pairedAt: Date
    }

    static let shared = CryptoManager()

    private let lock = NSLock()
    private let identityKey: Curve25519.KeyAgreement.PrivateKey
    private var devices: [PairedDevice]

    var identityPublicKey: Data { identityKey.publicKey.rawRepresentation }

    private init() {
        if let data = Self.keychainRead(service: Self.keychainService, account: Self.accountIdentity),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            identityKey = key
        } else {
            let newKey = Curve25519.KeyAgreement.PrivateKey()
            _ = Self.keychainWrite(service: Self.keychainService, account: Self.accountIdentity,
                                    data: newKey.rawRepresentation)
            identityKey = newKey
        }

        if let data = Self.keychainRead(service: Self.keychainService, account: Self.accountPairedDevices),
           let decoded = try? JSONDecoder().decode([PairedDevice].self, from: data) {
            devices = decoded
        } else {
            devices = []
        }
    }

    // MARK: - Gekoppelte Geräte

    func pairedDevices() -> [PairedDevice] {
        lock.lock(); defer { lock.unlock() }
        return devices.sorted { $0.pairedAt > $1.pairedAt }
    }

    func device(for id: UUID) -> PairedDevice? {
        lock.lock(); defer { lock.unlock() }
        return devices.first { $0.deviceID == id }
    }

    @discardableResult
    func addDevice(name: String, clientPublicKey: Data, psk: SymmetricKey) -> UUID {
        let id = UUID()
        let record = PairedDevice(
            deviceID: id, name: name, clientPublicKey: clientPublicKey,
            psk: psk.dataRepresentation, pairedAt: Date()
        )
        lock.lock()
        devices.append(record)
        persistLocked()
        lock.unlock()
        return id
    }

    func removeDevice(_ id: UUID) {
        lock.lock()
        devices.removeAll { $0.deviceID == id }
        persistLocked()
        lock.unlock()
    }

    /// Benennt ein gekoppeltes Gerät um: aktualisiert nur den Anzeigenamen im
    /// Keychain-Geräteeintrag (PSK/Public Key/Datum bleiben). Ein leerer bzw. nur
    /// aus Leerraum bestehender Name wird ignoriert (Rückgabe `false`).
    @discardableResult
    func renameDevice(_ id: UUID, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        guard let index = devices.firstIndex(where: { $0.deviceID == id }) else { return false }
        devices[index].name = trimmed
        persistLocked()
        return true
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(devices) else { return }
        _ = Self.keychainWrite(service: Self.keychainService, account: Self.accountPairedDevices, data: data)
    }

    // MARK: - Krypto-Ableitungen (docs/PROTOCOL-v2.md, „Phase 1 – Pairing“)

    func sharedSecret(withPeerPublicKey peerPublicKey: Data) throws -> SharedSecret {
        let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        return try identityKey.sharedSecretFromKeyAgreement(with: peerKey)
    }

    /// `PSK = HKDF-SHA256(ikm: shared, salt: "qrkb-pair-v2", info: clientPub‖hostPub, len: 32)`
    /// Delegiert an die reine Kernfunktion (siehe `CryptoCore` — identisches Schema).
    func derivePSK(shared: SharedSecret, clientPub: Data, hostPub: Data) -> SymmetricKey {
        CryptoCore.derivePSK(shared: shared, clientPub: clientPub, hostPub: hostPub)
    }

    /// `confirmKey = HKDF-SHA256(ikm: shared, salt: "qrkb-confirm-v2", info: clientPub‖hostPub, len: 32)`
    func deriveConfirmKey(shared: SharedSecret, clientPub: Data, hostPub: Data) -> SymmetricKey {
        CryptoCore.deriveConfirmKey(shared: shared, clientPub: clientPub, hostPub: hostPub)
    }

    /// `sessionKey = HKDF-SHA256(ikm: PSK, salt: clientNonce‖hostNonce, info: "qrkb-session-v2", len: 32)`
    static func deriveSessionKey(psk: SymmetricKey, clientNonce: Data, hostNonce: Data) -> SymmetricKey {
        CryptoCore.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonce)
    }

    static func symmetricKey(fromDeviceRecord data: Data) -> SymmetricKey {
        SymmetricKey(data: data)
    }

    // MARK: - Keychain (Generic Password, kSecAttrAccessibleAfterFirstUnlock)

    private static func keychainQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func keychainRead(service: String, account: String) -> Data? {
        var query = keychainQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func keychainWrite(service: String, account: String, data: Data) -> Bool {
        let query = keychainQuery(service: service, account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        return updateStatus == errSecSuccess
    }

    static func keychainDelete(service: String, account: String) {
        let query = keychainQuery(service: service, account: account)
        SecItemDelete(query as CFDictionary)
    }
}
