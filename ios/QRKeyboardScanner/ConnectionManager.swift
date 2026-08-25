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

/// Verwaltet Bonjour-Discovery (`_keystrokeqr._tcp`) und die verschlüsselte
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
    /// Name des aktuell (Phase 2) verbundenen Macs — für Statusanzeige und die
    /// „gefundene Macs“-Auswahl (Kennzeichnung „verbunden“). `nil`, sobald keine
    /// Sitzung mehr steht.
    @Published private(set) var connectedServiceName: String?

    /// Status eines gefundenen Macs relativ zum lokalen Zustand — steuert Beschriftung
    /// und Verhalten in der Mac-Auswahl (Wechsel zwischen mehreren Macs).
    enum MacStatus { case connected, paired, new, outdated }

    private let crypto = CryptoManager.shared
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isActive = false
    private var reconnectAttempts = 0
    private let queue = DispatchQueue(label: "de.timehrenfried.keystrokeqr.network")

    // Sitzungs-Kryptozustand der aktuellen Verbindung.
    private var sessionKey: SymmetricKey?
    private var sendSeq: UInt64 = 0
    private var lastRecvSeq: UInt64?

    /// `true`, sobald wir `session_hello` gesendet haben und auf `session_ready`
    /// warten (die WS-Verbindung stand also bereits auf `.ready`). Kernstück der
    /// Unterscheidung „host-seitig entkoppelt“ vs. „transienter Netzabriss“:
    /// bricht die Verbindung GENAU in diesem Fenster ab, hat der Host unser
    /// `session_hello` mit unbekannter `deviceID` verworfen (Gerät am Mac
    /// entfernt) — sein `session_error` geht bei seinem sofortigen `cancel()`
    /// häufig verloren, sodass wir es nicht als reines Netzproblem behandeln dürfen.
    private var awaitingSessionReady = false
    /// Zähler fehlgeschlagener Sitzungs-Handshakes je Servicename (ready→Abbruch,
    /// ohne je `session_ready` gesehen zu haben). Ab `handshakeFailureThreshold`
    /// werten wir das als `not_paired` (siehe `connectionLost`), statt endlos
    /// weiterzureconnecten.
    private var handshakeFailuresByService: [String: Int] = [:]
    /// Ab wie vielen aufeinanderfolgenden ready→Abbruch-ohne-`session_ready` wir
    /// einen Mac als „nicht mehr gekoppelt“ behandeln. 2 lässt einen einzelnen,
    /// echt transienten Abriss im schmalen Handshake-Fenster zu, fängt aber den
    /// deterministischen Host-Entkopplungs-Fall (jeder Versuch bricht direkt nach
    /// `session_hello` ab) verlässlich ab.
    private let handshakeFailureThreshold = 2

    // Pairing-Zustand (Phase 1) der aktuellen Verbindung, falls eine läuft.
    private var pairingCompletion: ((Result<CryptoManager.PairedMac, PairingError>) -> Void)?
    private var pairingServiceName: String?
    private var pairingOTP: String?
    /// Letzter Ausweg: bricht einen Pairing-Versuch ab, wenn der Mac GAR NICHT
    /// antwortet (kein `pair_ok`, kein `pair_error`, kein Verbindungsabbruch).
    /// Wird von jedem expliziten Pairing-Ergebnis sofort gecancelt, damit ein
    /// eintreffendes `pair_error` immer VOR dem Timeout gewinnt.
    private var pairingTimeoutTask: Task<Void, Never>?
    /// `true`, sobald wir `pair_confirm` gesendet haben und auf `pair_ok`/
    /// `pair_error` warten. Schließt der Host danach die Verbindung ohne
    /// verwertbares `pair_error` (der Frame kann beim harten `cancel()` des
    /// Hosts verlorengehen), werten wir das als falschen Code (häufigster Fall).
    private var pairingConfirmSent = false
    /// Obergrenze für einen einzelnen Pairing-Versuch (letzter Ausweg).
    private let pairingTimeout: Duration = .seconds(12)

    enum PairingError: Error {
        case notFound, connectionFailed, badOTP, closed, expired, invalidResponse, timedOut
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
        connectedServiceName = nil
        handshakeFailuresByService.removeAll()
        resetSessionCrypto()
        state = .idle
    }

    // MARK: - Bonjour-Browse

    private func startBrowser() {
        guard isActive else { return }
        browser?.cancel()

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let newBrowser = NWBrowser(
            for: .bonjour(type: "_keystrokeqr._tcp", domain: nil),
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

    /// Klassifiziert einen gefundenen Mac für die Auswahlliste: aktuell verbunden,
    /// gekoppelt (PSK vorhanden), neu (v2 ohne PSK) oder veraltet (nur v1).
    func status(for service: DiscoveredService) -> MacStatus {
        guard service.isV2 else { return .outdated }
        if connectedServiceName == service.name, case .connected = state { return .connected }
        return crypto.pairedMac(forServiceName: service.name) != nil ? .paired : .new
    }

    /// Nutzergesteuerter Wechsel zu einem ANDEREN gefundenen Mac — auch wenn bereits
    /// einer verbunden ist. Baut die laufende Sitzung sauber ab (Verbindung `cancel()`
    /// + `resetSessionCrypto()`, damit KEIN Nonce-/Sitzungsschlüssel zwischen Macs
    /// überlebt) und verbindet zum gewählten Mac bzw. bietet Pairing an, falls dort
    /// noch kein PSK vorliegt. Kein App-Neustart nötig.
    func switchTo(_ service: DiscoveredService) {
        guard isActive else { return }
        // Bereits mit genau diesem Mac verbunden? Aktive Sitzung nicht unnötig kappen.
        if connectedServiceName == service.name, case .connected = state { return }
        connection?.cancel()
        connection = nil
        resetSessionCrypto()
        connectedServiceName = nil
        showServicePicker = false
        // Wechsel ist ein bewusster Neuaufbau — evtl. Zähler dieses Ziels verwerfen.
        handshakeFailuresByService[service.name] = nil
        selectService(service)
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
        // Ab jetzt läuft der Sitzungs-Handshake: ein Abbruch VOR `session_ready`
        // fließt in die not_paired-vs-transient-Heuristik ein (siehe connectionLost).
        awaitingSessionReady = true
        send(SessionHelloMessage(deviceID: deviceID.uuidString, nonce: clientNonce.base64EncodedString()), on: connection)
    }

    private func connectionLost(_ lost: NWConnection) {
        guard connection === lost else { return }
        // Läuft gerade ein Pairing, darf der Empfangsschleifen-Fehler die
        // wartende Continuation NICHT lecken lassen (sonst hängt der Screen bis
        // zum NWConnection-Timeout — der ursprüngliche „Timeout statt Fehler").
        // Über die Pairing-Auswertung (mit Gnadenfrist für ein `pair_error`)
        // abwickeln statt über den Sitzungs-Teardown.
        if pairingCompletion != nil {
            pairingConnectionClosed()
            return
        }

        // not_paired-vs-transient-Heuristik: Brach die Verbindung ab, NACHDEM wir
        // `.ready` erreicht + `session_hello` gesendet hatten, aber BEVOR
        // `session_ready` kam, ist das der host-seitige „Gerät entfernt“-Fall.
        // Der Host schließt direkt nach dem hello (sein `session_error` geht dabei
        // oft verloren) — deshalb NICHT stumpf reconnecten, sondern nach wenigen
        // Wiederholungen entkoppeln und Neu-Pairing anbieten. Ein einzelner echt
        // transienter Abriss in diesem schmalen Fenster bleibt unter der Schwelle
        // und führt nur zu einem normalen Reconnect.
        if awaitingSessionReady, let serviceName = connectedServiceName,
           crypto.pairedMac(forServiceName: serviceName) != nil {
            let count = (handshakeFailuresByService[serviceName] ?? 0) + 1
            handshakeFailuresByService[serviceName] = count
            if count >= handshakeFailureThreshold {
                concludeNotPaired(serviceName: serviceName)
                return
            }
        }

        connection?.cancel()
        connection = nil
        resetSessionCrypto()
        connectedServiceName = nil
        guard isActive else { return }
        state = .disconnected
        scheduleRetry()
    }

    /// Der Host kennt unsere `deviceID` nicht (mehr): PSK lokal verwerfen, Verbindung
    /// sauber abbauen und **Neu-Pairing anbieten** (statt in eine stille Reconnect-
    /// Schleife zu laufen). Gemeinsamer Endpunkt für das explizite
    /// `session_error/not_paired` UND die Handshake-Heuristik (Fall, in dem der
    /// Host das `session_error`-Frame beim sofortigen `cancel()` verwirft).
    private func concludeNotPaired(serviceName: String) {
        awaitingSessionReady = false
        handshakeFailuresByService[serviceName] = nil
        // PSK/Mac-Eintrag für genau diesen Mac löschen — danach routet
        // `selectService` künftige Funde dieses Macs auf den Pairing-Screen,
        // sodass ein frisches Pairing (neuer `pair_hello`) möglich ist.
        crypto.removeMac(serviceName: serviceName)
        connection?.cancel()
        connection = nil
        resetSessionCrypto()
        connectedServiceName = nil
        // ContentView beobachtet dies und öffnet den Pairing-Screen.
        notPairedServiceName = serviceName
        guard isActive else { return }
        state = .disconnected
        scheduleRetry()
    }

    private func resetSessionCrypto() {
        sessionKey = nil
        sendSeq = 0
        lastRecvSeq = nil
        awaitingSessionReady = false
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
        // Handshake erfolgreich: Fenster-Flag schließen und Fehlversuchs-Zähler
        // dieses Macs zurücksetzen (der not_paired-Verdacht ist ausgeräumt).
        awaitingSessionReady = false
        handshakeFailuresByService[serviceName] = nil
        state = .connected(serviceName)
        _ = connection // Handshake abgeschlossen, Frames folgen ab jetzt.
    }

    private func handleSessionError(_ data: Data) {
        guard let msg = try? JSONDecoder().decode(SessionErrorMessage.self, from: data) else { return }
        if msg.error == "not_paired", let serviceName = connectedServiceName {
            // PSK ist auf dem Host nicht (mehr) bekannt: lokal verwerfen, Verbindung
            // sauber abbauen und Neu-Pairing anbieten (docs/PROTOCOL-v2.md, Phase 2).
            // Dies ist der schnelle, explizite Pfad; der host-seitige „Gerät
            // entfernt“-Fall wird zusätzlich über die Handshake-Heuristik gefangen,
            // falls dieses Frame verlorengeht.
            concludeNotPaired(serviceName: serviceName)
        } else {
            // Anderer/unbekannter Sitzungsfehler → nur Verbindung schließen
            // (regulärer Reconnect via connectionLost).
            connection?.cancel()
        }
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

        // Frischer Versuch: baut IMMER eine NEUE Pairing-Verbindung auf (neuer
        // `pair_hello`). Nach einem falschen Code hat der Mac laut Protokoll
        // bereits automatisch einen NEUEN OTP erzeugt — der nächste `pair()`-
        // Aufruf handshaked also gegen diesen neuen Code.
        let newConnection = makeConnection(to: service.endpoint)
        pairingOTP = otp
        pairingServiceName = service.name
        pairingConfirmSent = false

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
                        // Verbindung weg, bevor ein explizites Ergebnis kam:
                        // ein evtl. schon empfangenes `pair_error` gewinnt (kurze
                        // Gnadenfrist), sonst als Abbruch/falscher Code werten.
                        self.pairingConnectionClosed()
                    default:
                        break
                    }
                }
            }
            receiveLoop(on: newConnection)
            newConnection.start(queue: queue)
            // Letzter Ausweg: reagiert der Mac gar nicht, brechen wir sauber ab.
            armPairingTimeout()
        }
    }

    /// Startet den Pairing-Timeout neu (letzter Ausweg). Ein eintreffendes
    /// `pair_ok`/`pair_error` oder ein Verbindungsabbruch canceln ihn zuvor,
    /// sodass der Timeout NIE einen expliziten Fehler „überholt".
    private func armPairingTimeout() {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.pairingTimeout ?? .seconds(12))
            guard let self, !Task.isCancelled, self.pairingCompletion != nil else { return }
            self.finishPairing(.failure(.timedOut))
        }
    }

    /// Die Pairing-Verbindung wurde geschlossen (Host-`cancel()` nach `pair_error`
    /// oder echter Abbruch). Kurze Gnadenfrist, damit ein bereits im Empfangspuffer
    /// liegendes `pair_error`/`pair_ok` noch verarbeitet wird und GEWINNT; erst
    /// danach werten wir den reinen Verbindungsverlust aus.
    private func pairingConnectionClosed() {
        guard pairingCompletion != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, self.pairingCompletion != nil else { return }
            // Kein explizites `pair_error` eingetroffen. Hatten wir schon
            // `pair_confirm` gesendet, ist ein verworfener Code die mit Abstand
            // häufigste Ursache (der Host schließt danach hart) → als falscher
            // Code melden; sonst technischer Verbindungsfehler.
            self.finishPairing(.failure(self.pairingConfirmSent ? .badOTP : .connectionFailed))
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

        pairingConfirmSent = true
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
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        pairingConfirmSent = false
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
