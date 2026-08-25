import Foundation
import CryptoKit
@testable import QRKeyboardHost

extension SymmetricKey {
    /// Rohbytes des Schlüssels — nur für Vergleiche/Assertions in den Tests.
    var rawData: Data { withUnsafeBytes { Data($0) } }
}

enum TestKeys {
    /// Erzeugt ein X25519-Schlüsselpaar-Setup und liefert die beidseitig
    /// gleichen `SharedSecret`s plus die Public Keys (Base64-Rohbytes), analog zum
    /// Pairing-Handshake in docs/PROTOCOL-v2.md.
    static func handshake() throws -> (sharedClient: SharedSecret, sharedHost: SharedSecret,
                                       clientPub: Data, hostPub: Data) {
        let clientPriv = Curve25519.KeyAgreement.PrivateKey()
        let hostPriv = Curve25519.KeyAgreement.PrivateKey()
        let clientPub = clientPriv.publicKey.rawRepresentation
        let hostPub = hostPriv.publicKey.rawRepresentation
        let sharedClient = try clientPriv.sharedSecretFromKeyAgreement(with: hostPriv.publicKey)
        let sharedHost = try hostPriv.sharedSecretFromKeyAgreement(with: clientPriv.publicKey)
        return (sharedClient, sharedHost, clientPub, hostPub)
    }
}
