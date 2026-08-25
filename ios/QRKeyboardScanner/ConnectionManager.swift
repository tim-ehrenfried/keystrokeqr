import Foundation
import Network
import Combine
import CryptoKit

// MARK: - Nachrichten (siehe docs/PROTOCOL-v2.md)

/// Nutzlast einmal entschlüsselt — unverändert gegenüber v1.
struct ScanMessage: Encodable {
    let type = "scan"
    let text: String
    let autoEnter: Bool
    let autoTab: Bool
}

struct AckMessage: Decodable {
    let type: String
    let ok: Bool
    let error: String?
}

func encodeMessage<T: Encodable>(_ value: T) -> Data {
    (try? JSONEncoder().encode(value)) ?? Data()
}

struct MessageEnvelope: Decodable {
    let type: String
}

// Phase 1 – Pairing (Klartext, nur während des Pairing-Vorgangs)

struct PairHelloMessage: Encodable {
    let type = "pair_hello"
    let clientPub: String
    let deviceName: String
}

struct PairChallengeMessage: Decodable {
    let type: String
    let hostPub: String
}

struct PairConfirmMessage: Encodable {
    let type = "pair_confirm"
    let mac: String
}

struct PairOkMessage: Decodable {
    let type: String
    let deviceID: String
    let hostName: String
}

struct PairErrorMessage: Decodable {
    let type: String
    let error: String
}

// Phase 2 – Gesicherte Sitzung

struct SessionHelloMessage: Encodable {
    let type = "session_hello"
    let deviceID: String
    let nonce: String
}

struct SessionReadyMessage: Decodable {
    let type: String
    let nonce: String
}

struct SessionErrorMessage: Decodable {
    let type: String
    let error: String
}

struct EncFrameMessage: Codable {
    let type: String
    let seq: UInt64
    let ct: String

    init(seq: UInt64, ct: String) {
        self.type = "enc"
        self.seq = seq
        self.ct = ct
    }
}

/// Verwaltet Bonjour-Discovery (`_qr-keyboard._tcp`) und die verschlüsselte
/// WebSocket-Verbindung zum Mac-Host via Network.framework, gemäß
/// docs/PROTOCOL-v2.md. Der Port kommt IMMER aus der Bonjour-Auflösung
/// (NWEndpoint.service), niemals hartkodiert.
@MainActor
final class ConnectionManager: ObservableObject {

    enum ConnectionState: Equatable {
        case idle
        case browsing
        case connecting(String)
        case connected(String)
        case disconnected
    }

    struct DiscoveredService: Identifiable, Equatable {
        let name: String
        let endpoint: NWEndpoint
        /// `true`, wenn der Host per Bonjour-TXT `v=2` meldet (verschlüsselt/
        /// gekoppelt) — `false` bei reinem v1-Host („Mac-App aktualisieren“).
        let isV2: Bool
        var id: String { name }
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var services: [DiscoveredService] = []
    @Published var showServicePicker = false
    /// Host hat gemeldet, dass die Bedienungshilfen-Berechtigung auf dem Mac fehlt.
    @Published var hostAccessibilityDenied = false
    /// Ein v2-Host wurde gefunden, für den (noch) kein PSK vorliegt — Pairing-UI zeigen.
    /// Beschreibbar (ContentView setzt via `$`-Binding auf `nil` beim Dismiss).
    @Published var pendingPairingService: DiscoveredService?
    /// Nur ein v1-Host wurde gefunden — Mac-App muss aktualisiert werden.
    @Published var outdatedHostDetected = false
    /// Host kennt unsere `deviceID` nicht (mehr) — PSK wurde lokal verworfen, neu koppeln nötig.
    @Published var notPairedServiceName: String?

    private let crypto = CryptoManager.shared
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isActive = false
    private var reconnectAttempts = 0
    private let queue = DispatchQueue(label: "de.timehrenfried.qr-keyboard-scanner.network")

    // Sitzungs-Kryptozustand der aktuellen Verbindung.
    private var sessionKey: SymmetricKey?
    private var sendSeq: UInt64 = 0
    private var lastRecvSeq: UInt64?
    private var connectedServiceName: String?

    // Pairing-Zustand (Phase 1) der aktuellen Verbindung, falls eine läuft.
    private var pairingCompletion: ((Result<CryptoManager.PairedMac, PairingError>) -> Void)?
    private var pairingServiceName: String?
    private var pairingOTP: String?

    enum PairingError: Error {
        case notFound, connectionFailed, badOTP, closed, expired, invalidResponse
    }

    // MARK: - Lifecycle

    /// Beim App-Start bzw. wenn die App aktiv wird aufrufen.
    func start() {
        guard !isActive else { return }
        isActive = true
        reconnectAttempts = 0
        startBrowser()
    }

    /// Wenn die App inaktiv wird aufrufen: alles abbauen.
    func stop() {
        isActive = false
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
        services = []
        showServicePicker = false
        state = .idle
    }

    // MARK: - Bonjour-Browse

    private func startBrowser() {
        guard isActive else { return }
        browser?.cancel()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let newBrowser = NWBrowser(
            for: .bonjour(type: "_qr-keyboard._tcp", domain: nil),
            using: parameters
        )
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handleBrowseResults(results)
            }
        }
        newBrowser.stateUpdateHandler = { [weak self] browserState in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                if case .failed = browserState {
                    self.scheduleRetry()
                }
            }
        }
        browser = newBrowser
        if connection == nil {
            state = .browsing
        }
        newBrowser.start(queue: queue)
    }

    /// Bewertet die Protokollversion aus dem Bonjour-TXT-Record.
    ///
    /// Wichtig: `NWBrowser` liefert den TXT-Record in den Browse-Ergebnissen
    /// NICHT zuverlässig mit (häufig `.none`, obwohl der Host `v=2` announced).
    /// Deshalb gilt ein Host nur dann als veraltet, wenn er sich **explizit**
    /// als `v=1` meldet. Fehlt der Record oder steht `v=2` drin, behandeln wir
    /// ihn als v2 — die tatsächliche Version wird beim Sitzungs-/Pairing-
    /// Handshake ohnehin final geprüft (falscher Handshake ⇒ Verbindung scheitert).
    private static func isV2(_ result: NWBrowser.Result) -> Bool {
        guard case let .bonjour(txt) = result.metadata else { return true }
        return txt.dictionary["v"] != "1"
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard isActive else { return }
        services = results
            .compactMap { result -> DiscoveredService? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredService(name: name, endpoint: result.endpoint, isV2: Self.isV2(result))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard connection == nil else { return }
        if services.count == 1 {
            selectService(services[0])
        } else if services.count > 1 {
            showServicePicker = true
        }
    }

    /// Entscheidet je gefundenem Dienst: verbinden (PSK vorhanden), Pairing
    /// anbieten (v2 ohne PSK) oder Hinweis „Mac-App aktualisieren“ (v1).
    /// Öffentlich, damit die Auswahl-Liste (mehrere gefundene Macs) dieselbe
    /// Logik nutzen kann wie der automatische Single-Service-Connect.
    func selectService(_ service: DiscoveredService) {
        guard service.isV2 else {
            outdatedHostDetected = true
            return
        }
        if crypto.pairedMac(forServiceName: service.name) != nil {
            connect(to: service)
        } else {
            pendingPairingService = service
        }
    }

    // MARK: - Phase 2: Verbindung (gekoppelte Geräte)

    /// Verbindet zum gewählten, bereits gekoppelten Bonjour-Service und führt
    /// den Sitzungs-Handshake (`session_hello`/`session_ready`) durch.
    func connect(to service: DiscoveredService) {
        guard isActive, let mac = crypto.pairedMac(forServiceName: service.name) else { return }
        showServicePicker = false
        outdatedHostDetected = false
        pendingPairingService = nil
        connection?.cancel()
        resetSessionCrypto()

        let newConnection = makeConnection(to: service.endpoint)
        connection = newConnection
        connectedServiceName = service.name
        state = .connecting(service.name)

        newConnection.stateUpdateHandler = { [weak self] connectionState in
            Task { @MainActor [weak self] in
                self?.handleConnectionState(connectionState, serviceName: service.name, connection: newConnection)
            }
        }
        receiveLoop(on: newConnection)
        newConnection.start(queue: queue)

        // Sobald die Verbindung steht, startet handleConnectionState(.ready)
        // den session_hello-Handshake (siehe unten).
        pendingSessionHandshakeDeviceID = mac.deviceID
        pendingSessionHandshakePSK = mac.psk
    }

    private var pendingSessionHandshakeDeviceID: UUID?
    private var pendingSessionHandshakePSK: Data?
    private var pendingClientNonce: Data?

    private func makeConnection(to endpoint: NWEndpoint) -> NWConnection {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        parameters.includePeerToPeer = true
        return NWConnection(to: endpoint, using: parameters)
    }

    private func handleConnectionState(
        _ connectionState: NWConnection.State,
        serviceName: String,
        connection: NWConnection
    ) {
        guard self.connection === connection, isActive else { return }
        switch connectionState {
        case .ready:
            reconnectAttempts = 0
            state = .connecting(serviceName) // erst nach session_ready wirklich „verbunden“
            beginSessionHandshake(on: connection)
        case .failed, .cancelled:
            connectionLost(connection)
        case .waiting:
            state = .connecting(serviceName)
        default:
            break
        }
    }

    private func beginSessionHandshake(on connection: NWConnection) {
        guard let deviceID = pendingSessionHandshakeDeviceID else { return }
        var generator = SystemRandomNumberGenerator()
        let clientNonce = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
        pendingClientNonce = clientNonce
        send(SessionHelloMessage(deviceID: deviceID.uuidString, nonce: clientNonce.base64EncodedString()), on: connection)
    }

    private func connectionLost(_ lost: NWConnection) {
        guard connection === lost else { return }
        connection?.cancel()
        connection = nil
        resetSessionCrypto()
        guard isActive else { return }
        state = .disconnected
        scheduleRetry()
    }

    private func resetSessionCrypto() {
        sessionKey = nil
        sendSeq = 0
        lastRecvSeq = nil
        pendingSessionHandshakeDeviceID = nil
        pendingSessionHandshakePSK = nil
        pendingClientNonce = nil
    }

    /// Kurzer Backoff, dann Bonjour-Browse neu starten → Auto-Reconnect.
    private func scheduleRetry() {
        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts), 5.0)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isActive, self.connection == nil else { return }
            self.startBrowser()
        }
    }

    // MARK: - Senden / Empfangen (Transport)

    private func send<T: Encodable>(_ message: T, on connection: NWConnection) {
        let data = encodeMessage(message)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "msg", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    /// Sendet einen gescannten Code als verschlüsselten `enc`-Frame.
    func send(text: String, autoEnter: Bool, autoTab: Bool) {
        guard let connection, case .connected = state, let sessionKey else { return }
        let message = ScanMessage(text: text, autoEnter: autoEnter, autoTab: autoTab)
        let plaintext = encodeMessage(message)
        let seq = sendSeq
        sendSeq += 1
        guard let ct = try? SecureFrame.seal(plaintext, key: sessionKey, prefix: FrameDirection.clientToHost, seq: seq) else { return }
        send(EncFrameMessage(seq: seq, ct: ct.base64EncodedString()), on: connection)
    }

    nonisolated private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { @MainActor [weak self] in
                    self?.handleIncoming(data, connection: connection)
                }
            }
            if error == nil {
                self.receiveLoop(on: connection)
            } else {
                Task { @MainActor [weak self] in
                    self?.connectionLost(connection)
                }
            }
        }
    }

    private func handleIncoming(_ data: Data, connection: NWConnection) {
        guard self.connection === connection else { return }
        guard let envelope = try? JSONDecoder().decode(MessageEnvelope.self, from: data) else { return }

        switch envelope.type {
        case "session_ready":
            handleSessionReady(data)
        case "session_error":
            handleSessionError(data)
        case "enc":
            handleEncFrame(data)
        case "pair_challenge":
            handlePairChallenge(data)
        case "pair_ok":
            handlePairOk(data)
        case "pair_error":
            handlePairError(data)
        default:
            break
        }
    }

    // MARK: - Phase 2: Sitzungs-Handshake (Antworten)

    private func handleSessionReady(_ data: Data) {
        guard let connection,
              let msg = try? JSONDecoder().decode(SessionReadyMessage.self, from: data),
              msg.type == "session_ready",
              let hostNonce = Data(base64Encoded: msg.nonce),
              let clientNonce = pendingClientNonce,
              let pskData = pendingSessionHandshakePSK,
              let serviceName = connectedServiceName else { return }

        let psk = CryptoManager.symmetricKey(fromRecord: pskData)
        sessionKey = CryptoManager.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonce)
        sendSeq = 0
        lastRecvSeq = nil
        state = .connected(serviceName)
        _ = connection // Handshake abgeschlossen, Frames folgen ab jetzt.
    }

    private func handleSessionError(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(SessionErrorMessage.self, from: data) else { return }
        if msg.error == "not_paired", let serviceName = connectedServiceName {
            // PSK ist auf dem Host nicht (mehr) bekannt: lokal verwerfen und
            // Neu-Pairing anbieten (siehe docs/PROTOCOL-v2.md, Phase 2).
            crypto.removeMac(serviceName: serviceName)
            notPairedServiceName = serviceName
        }
        connection?.cancel()
    }

    private func handleEncFrame(_ data: Data) {
        guard let sessionKey else { return }
        guard let msg = try? JSONDecoder().decode(EncFrameMessage.self, from: data),
              msg.type == "enc",
              let ct = Data(base64Encoded: msg.ct) else { return }
        if let last = lastRecvSeq, msg.seq <= last { return } // Replay-Schutz
        guard let plaintext = try? SecureFrame.open(ct, key: sessionKey, prefix: FrameDirection.hostToClient, seq: msg.seq) else {
            connection?.cancel()
            return
        }
        lastRecvSeq = msg.seq

        guard let ack = try? JSONDecoder().decode(AckMessage.self, from: plaintext), ack.type == "ack" else { return }
        if ack.ok {
            hostAccessibilityDenied = false
        } else if ack.error == "accessibility_denied" {
            hostAccessibilityDenied = true
        }
    }

    // MARK: - Phase 1: Pairing

    /// Startet das Pairing mit einem gefundenen v2-Host: verbindet, sendet
    /// `pair_hello`, wartet auf `pair_challenge`, bestätigt mit dem OTP.
    /// `completion` wird auf dem MainActor aufgerufen.
    func pair(with service: DiscoveredService, otp: String, deviceName: String) async -> Result<CryptoManager.PairedMac, PairingError> {
        connection?.cancel()
        resetSessionCrypto()

        let newConnection = makeConnection(to: service.endpoint)
        pairingOTP = otp
        pairingServiceName = service.name

        return await withCheckedContinuation { continuation in
            pairingCompletion = { result in
                continuation.resume(returning: result)
            }
            connection = newConnection
            newConnection.stateUpdateHandler = { [weak self] connectionState in
                Task { @MainActor [weak self] in
                    guard let self, self.connection === newConnection else { return }
                    switch connectionState {
                    case .ready:
                        self.send(
                            PairHelloMessage(
                                clientPub: self.crypto.identityPublicKey.base64EncodedString(),
                                deviceName: deviceName
                            ),
                            on: newConnection
                        )
                    case .failed, .cancelled:
                        self.finishPairing(.failure(.connectionFailed))
                    default:
                        break
                    }
                }
            }
            receiveLoop(on: newConnection)
            newConnection.start(queue: queue)
        }
    }

    private func handlePairChallenge(_ data: Data) {
        guard let connection,
              let msg = try? JSONDecoder().decode(PairChallengeMessage.self, from: data),
              msg.type == "pair_challenge",
              let hostPub = Data(base64Encoded: msg.hostPub),
              let otp = pairingOTP,
              let shared = try? crypto.sharedSecret(withPeerPublicKey: hostPub) else {
            finishPairing(.failure(.invalidResponse))
            return
        }
        let clientPub = crypto.identityPublicKey
        let confirmKey = crypto.deriveConfirmKey(shared: shared, clientPub: clientPub, hostPub: hostPub)
        let mac = CryptoManager.confirmationMAC(otp: otp, confirmKey: confirmKey)

        // PSK bereits jetzt lokal ableiten — wird nur bei pair_ok persistiert.
        pendingPairingPSK = crypto.derivePSK(shared: shared, clientPub: clientPub, hostPub: hostPub)
        pendingPairingHostPub = hostPub

        send(PairConfirmMessage(mac: mac.base64EncodedString()), on: connection)
    }

    private var pendingPairingPSK: SymmetricKey?
    private var pendingPairingHostPub: Data?

    private func handlePairOk(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(PairOkMessage.self, from: data),
              msg.type == "pair_ok",
              let deviceID = UUID(uuidString: msg.deviceID),
              let psk = pendingPairingPSK,
              let hostPub = pendingPairingHostPub,
              let serviceName = pairingServiceName else {
            finishPairing(.failure(.invalidResponse))
            return
        }
        let record = crypto.addOrUpdateMac(
            serviceName: serviceName, hostName: msg.hostName, hostPublicKey: hostPub,
            deviceID: deviceID, psk: psk
        )
        finishPairing(.success(record))
    }

    private func handlePairError(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(PairErrorMessage.self, from: data) else {
            finishPairing(.failure(.invalidResponse))
            return
        }
        switch msg.error {
        case "bad_otp": finishPairing(.failure(.badOTP))
        case "pairing_expired": finishPairing(.failure(.expired))
        default: finishPairing(.failure(.closed))
        }
    }

    private func finishPairing(_ result: Result<CryptoManager.PairedMac, PairingError>) {
        connection?.cancel()
        connection = nil
        pendingPairingPSK = nil
        pendingPairingHostPub = nil
        pairingOTP = nil
        pairingServiceName = nil
        let completion = pairingCompletion
        pairingCompletion = nil
        completion?(result)
        // Nach Pairing regulär neu verbinden (Phase 2), falls die App noch aktiv ist.
        if isActive, connection == nil {
            state = .disconnected
            scheduleRetry()
        }
    }

    // MARK: - Geräteverwaltung

    func pairedMacs() -> [CryptoManager.PairedMac] {
        crypto.pairedMacs()
    }

    /// Entkoppelt einen Mac: PSK lokal löschen, laufende Verbindung zu ihm trennen.
    func unpair(serviceName: String) {
        crypto.removeMac(serviceName: serviceName)
        if connectedServiceName == serviceName {
            connection?.cancel()
        }
    }
}
