import Foundation
import CryptoKit
import Security

/// Nonce-Richtungspräfixe für verschlüsselte Frames (siehe docs/PROTOCOL-v2.md,
/// Abschnitt „Verschlüsselte Frames“). MÜSSEN mit
/// `macos/Sources/QRKeyboardHost/CryptoManager.swift` identisch sein — sonst
/// schlägt ChaChaPoly.open auf der Gegenseite fehl.
enum FrameDirection {
    /// Client (dieses iPhone) → Host.
    static let clientToHost: [UInt8] = [0x71, 0x6B, 0x63, 0x31] // "qkc1"
    /// Host → Client.
    static let hostToClient: [UInt8] = [0x71, 0x6B, 0x68, 0x31] // "qkh1"
}

/// Verschlüsselt/entschlüsselt Nutz-Frames gemäß docs/PROTOCOL-v2.md.
///
/// Abweichung von der wörtlichen Spec-Formulierung „ChaChaPoly combined
/// (nonce implizit via seq)“: `ChaChaPoly.SealedBox.combined` in CryptoKit
/// enthält IMMER auch den 12-Byte-Nonce-Präfix — das widerspräche „nonce
/// implizit via seq“. Deshalb wird bewusst nur `ciphertext‖tag` (ohne Nonce)
/// übertragen; der Nonce wird auf beiden Seiten deterministisch aus
/// Richtungspräfix + big-endian `seq` rekonstruiert (siehe präzisierte
/// PROTOCOL-v2.md).
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

/// Persistente Identität + gekoppelte Macs in der Keychain
/// (Service `de.timehrenfried.keystrokeqr`), gemäß docs/PROTOCOL-v2.md.
/// Threadsicher (NSLock) — wird sowohl vom `ConnectionManager` (MainActor)
/// als auch von der Pairing-/Verwaltungs-UI genutzt.
final class CryptoManager: @unchecked Sendable {

    static let keychainService = "de.timehrenfried.keystrokeqr"
    private static let accountIdentity = "identity"
    private static let accountPairedMacs = "paired-macs"

    /// Ein gekoppelter Mac. Korreliert über den Bonjour-Servicenamen
    /// (== Mac-Hostname), analog zur bestehenden v1-Geräteauswahl in
    /// `ConnectionManager` — der Host selbst kennt/versendet diesen Namen
    /// nicht separat als stabile ID, daher diese lokale (client-seitige)
    /// Design-Entscheidung.
    struct PairedMac: Codable, Identifiable {
        var id: String { serviceName }
        let serviceName: String
        var hostName: String
        let hostPublicKey: Data
        let deviceID: UUID
        let psk: Data
        let pairedAt: Date
    }

    static let shared = CryptoManager()

    private let lock = NSLock()
    private let identityKey: Curve25519.KeyAgreement.PrivateKey
    private var macs: [PairedMac]

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

        if let data = Self.keychainRead(service: Self.keychainService, account: Self.accountPairedMacs),
           let decoded = try? JSONDecoder().decode([PairedMac].self, from: data) {
            macs = decoded
        } else {
            macs = []
        }
    }

    // MARK: - Gekoppelte Macs

    func pairedMacs() -> [PairedMac] {
        lock.lock(); defer { lock.unlock() }
        return macs.sorted { $0.pairedAt > $1.pairedAt }
    }

    func pairedMac(forServiceName name: String) -> PairedMac? {
        lock.lock(); defer { lock.unlock() }
        return macs.first { $0.serviceName == name }
    }

    @discardableResult
    func addOrUpdateMac(
        serviceName: String, hostName: String, hostPublicKey: Data, deviceID: UUID, psk: SymmetricKey
    ) -> PairedMac {
        let record = PairedMac(
            serviceName: serviceName, hostName: hostName, hostPublicKey: hostPublicKey,
            deviceID: deviceID, psk: psk.dataRepresentation, pairedAt: Date()
        )
        lock.lock()
        macs.removeAll { $0.serviceName == serviceName }
        macs.append(record)
        persistLocked()
        lock.unlock()
        return record
    }

    func removeMac(serviceName: String) {
        lock.lock()
        macs.removeAll { $0.serviceName == serviceName }
        persistLocked()
        lock.unlock()
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(macs) else { return }
        _ = Self.keychainWrite(service: Self.keychainService, account: Self.accountPairedMacs, data: data)
    }

    // MARK: - Krypto-Ableitungen (docs/PROTOCOL-v2.md, „Phase 1 – Pairing“)

    func sharedSecret(withPeerPublicKey peerPublicKey: Data) throws -> SharedSecret {
        let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
        return try identityKey.sharedSecretFromKeyAgreement(with: peerKey)
    }

    /// `PSK = HKDF-SHA256(ikm: shared, salt: "qrkb-pair-v2", info: clientPub‖hostPub, len: 32)`
    func derivePSK(shared: SharedSecret, clientPub: Data, hostPub: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("qrkb-pair-v2".utf8),
            sharedInfo: clientPub + hostPub,
            outputByteCount: 32
        )
    }

    /// `confirmKey = HKDF-SHA256(ikm: shared, salt: "qrkb-confirm-v2", info: clientPub‖hostPub, len: 32)`
    func deriveConfirmKey(shared: SharedSecret, clientPub: Data, hostPub: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("qrkb-confirm-v2".utf8),
            sharedInfo: clientPub + hostPub,
            outputByteCount: 32
        )
    }

    /// `sessionKey = HKDF-SHA256(ikm: PSK, salt: clientNonce‖hostNonce, info: "qrkb-session-v2", len: 32)`
    static func deriveSessionKey(psk: SymmetricKey, clientNonce: Data, hostNonce: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: psk,
            salt: clientNonce + hostNonce,
            info: Data("qrkb-session-v2".utf8),
            outputByteCount: 32
        )
    }

    static func symmetricKey(fromRecord data: Data) -> SymmetricKey {
        SymmetricKey(data: data)
    }

    /// `HMAC(confirmKey, OTP)` — für `pair_confirm` (Client-Seite).
    static func confirmationMAC(otp: String, confirmKey: SymmetricKey) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(otp.utf8), using: confirmKey)
        return Data(mac)
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
