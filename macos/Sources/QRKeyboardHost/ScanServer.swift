import Foundation
import Network
import CryptoKit

/// WebSocket-Server gemäß docs/PROTOCOL-v2.md:
/// - NWListener (TCP + NWProtocolWebSocket, autoReplyPing)
/// - Fester Port 8080, Fallback auf beliebigen freien Port
/// - Bonjour-Advertising als `_keystrokeqr._tcp` mit TXT `v=2`
/// - Pro Verbindung: entweder Pairing-Handshake (Phase 1, nur im Pairing-
///   Fenster gültig) oder Sitzungs-Handshake (Phase 2, nur gekoppelte Geräte),
///   danach ausschließlich verschlüsselte `enc`-Frames.
final class ScanServer: @unchecked Sendable {

    static let serviceType = "_keystrokeqr._tcp"
    static let preferredPort: UInt16 = 8080

    /// DoS-Schutz: maximale Größe eines WebSocket-Frames in Bytes.
    static let maximumMessageSize = 65_536
    /// DoS-Schutz: maximale Länge von `text` in UTF-16-Einheiten.
    static let maximumTextLength = 8_192

    /// Zustand für die UI. Wird immer auf dem Main Thread gemeldet.
    struct State: Sendable {
        var activeSessionCount: Int = 0
        var port: UInt16? = nil
        var serviceName: String = ""
    }

    /// UI-Callback; wird auf DispatchQueue.main aufgerufen.
    var onStateChange: (@Sendable (State) -> Void)?

    private let queue = DispatchQueue(label: "de.timehrenfried.keystrokeqr.host.server")
    private let injector: KeyInjector
    private let crypto: CryptoManager
    private let pairingCoordinator: PairingCoordinator
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ConnectionContext] = [:]
    private var state = State()
    private let serviceName: String

    init(injector: KeyInjector, crypto: CryptoManager, pairingCoordinator: PairingCoordinator) {
        self.injector = injector
        self.crypto = crypto
        self.pairingCoordinator = pairingCoordinator
        self.serviceName = Host.current().localizedName ?? "KeystrokeQR Host"
        self.state.serviceName = serviceName
    }

    func start() {
        queue.async { [weak self] in
            self?.startListener(fixedPort: Self.preferredPort)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for context in self.connections.values {
                context.connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    /// Trennt alle aktiven Sitzungen eines (gerade entkoppelten) Geräts.
    func disconnectDevice(_ deviceID: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            for context in self.connections.values where context.deviceID == deviceID {
                context.connection.cancel()
            }
        }
    }

    // MARK: - Verbindungskontext

    /// Zustand einer einzelnen TCP/WebSocket-Verbindung. Frisch verbundene
    /// Clients starten in `.awaitingHello` und entscheiden per erster
    /// Nachricht (`pair_hello` oder `session_hello`), welche Phase folgt.
    /// Ausschließlich auf `queue` (der seriellen Server-Queue) gelesen/geschrieben.
    private final class ConnectionContext: @unchecked Sendable {
        enum Phase {
            case awaitingHello
            case pairingChallengeSent
            case sessionActive
        }

        let connection: NWConnection
        var phase: Phase = .awaitingHello

        // Pairing (Phase 1)
        var pendingClientPub: Data?
        var pendingDeviceName: String?

        // Sitzung (Phase 2)
        var sessionKey: SymmetricKey?
        var deviceID: UUID?
        var deviceName: String?
        var sendSeq: UInt64 = 0
        var lastRecvSeq: UInt64?

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    // MARK: - Listener

    /// Startet den Listener. `fixedPort == nil` bedeutet: beliebiger freier Port.
    private func startListener(fixedPort: UInt16?) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsOptions.maximumMessageSize = Self.maximumMessageSize
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let newListener: NWListener
        do {
            if let fixedPort, let port = NWEndpoint.Port(rawValue: fixedPort) {
                newListener = try NWListener(using: parameters, on: port)
            } else {
                newListener = try NWListener(using: parameters)
            }
        } catch {
            if fixedPort != nil {
                NSLog("QRKeyboardHost: Port %d nicht verfügbar (%@), weiche auf freien Port aus.",
                      Int(fixedPort ?? 0), String(describing: error))
                startListener(fixedPort: nil)
            } else {
                NSLog("QRKeyboardHost: Listener konnte nicht erstellt werden: %@",
                      String(describing: error))
            }
            return
        }

        // Bonjour-Advertising: Service-Name = Hostname des Macs, TXT v=2.
        var txtData = Data()
        let entry = Data("v=2".utf8)
        txtData.append(UInt8(entry.count))
        txtData.append(entry)
        newListener.service = NWListener.Service(
            name: serviceName,
            type: Self.serviceType,
            domain: nil,
            txtRecord: txtData
        )

        newListener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.state.port = newListener.port?.rawValue
                self.publishState()
                NSLog("QRKeyboardHost: Listener bereit auf Port %d.",
                      Int(newListener.port?.rawValue ?? 0))
            case .failed(let error):
                if fixedPort != nil, case .posix(let code) = error, code == .EADDRINUSE {
                    NSLog("QRKeyboardHost: Port %d belegt, weiche auf freien Port aus.",
                          Int(fixedPort ?? 0))
                    newListener.cancel()
                    self.startListener(fixedPort: nil)
                } else {
                    NSLog("QRKeyboardHost: Listener fehlgeschlagen: %@",
                          String(describing: error))
                    self.state.port = nil
                    self.publishState()
                }
            case .cancelled:
                break
            default:
                break
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.queue.async {
                self?.accept(connection)
            }
        }

        listener = newListener
        newListener.start(queue: queue)
    }

    // MARK: - Verbindungen

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        let context = ConnectionContext(connection: connection)
        connections[id] = context

        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.publishState()
                self.receiveNext(on: connection)
            case .failed, .cancelled:
                self.connections.removeValue(forKey: id)
                self.publishState()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let error {
                NSLog("QRKeyboardHost: Empfangsfehler: %@", String(describing: error))
                connection.cancel()
                return
            }

            var isClose = false
            if let context,
               let metadata = context.protocolMetadata(definition: NWProtocolWebSocket.definition)
                   as? NWProtocolWebSocket.Metadata,
               metadata.opcode == .close {
                isClose = true
            }

            if isClose {
                connection.cancel()
                return
            }

            if let data, !data.isEmpty {
                self.handleMessage(data, on: connection)
            }
            self.receiveNext(on: connection)
        }
    }

    // MARK: - Nachrichten-Dispatch

    private func handleMessage(_ data: Data, on connection: NWConnection) {
        guard let ctx = connections[ObjectIdentifier(connection)] else { return }
        guard let envelope = try? JSONDecoder().decode(MessageEnvelope.self, from: data) else {
            connection.cancel()
            return
        }

        switch envelope.type {
        case "pair_hello":
            handlePairHello(data, context: ctx)
        case "pair_confirm":
            handlePairConfirm(data, context: ctx)
        case "session_hello":
            handleSessionHello(data, context: ctx)
        case "enc":
            handleEncFrame(data, context: ctx)
        default:
            connection.cancel()
        }
    }

    // MARK: - Phase 1: Pairing

    private func handlePairHello(_ data: Data, context ctx: ConnectionContext) {
        guard ctx.phase == .awaitingHello,
              let msg = try? JSONDecoder().decode(PairHelloMessage.self, from: data),
              msg.type == "pair_hello",
              let clientPub = Data(base64Encoded: msg.clientPub),
              !msg.deviceName.isEmpty else {
            sendPairError(.badOTP, on: ctx.connection)
            ctx.connection.cancel()
            return
        }
        guard pairingCoordinator.isOpen else {
            sendPairError(.pairingClosed, on: ctx.connection)
            ctx.connection.cancel()
            return
        }

        ctx.pendingClientPub = clientPub
        ctx.pendingDeviceName = msg.deviceName
        ctx.phase = .pairingChallengeSent
        send(PairChallengeMessage(hostPub: crypto.identityPublicKey.base64EncodedString()), on: ctx.connection)
    }

    private func handlePairConfirm(_ data: Data, context ctx: ConnectionContext) {
        guard ctx.phase == .pairingChallengeSent,
              let clientPub = ctx.pendingClientPub,
              let deviceName = ctx.pendingDeviceName,
              let msg = try? JSONDecoder().decode(PairConfirmMessage.self, from: data),
              msg.type == "pair_confirm",
              let macData = Data(base64Encoded: msg.mac),
              let shared = try? crypto.sharedSecret(withPeerPublicKey: clientPub) else {
            sendPairError(.badOTP, on: ctx.connection)
            ctx.connection.cancel()
            return
        }

        let hostPub = crypto.identityPublicKey
        let confirmKey = crypto.deriveConfirmKey(shared: shared, clientPub: clientPub, hostPub: hostPub)

        switch pairingCoordinator.attemptConfirm(mac: macData, confirmKey: confirmKey) {
        case .success:
            let psk = crypto.derivePSK(shared: shared, clientPub: clientPub, hostPub: hostPub)
            let deviceID = crypto.addDevice(name: deviceName, clientPublicKey: clientPub, psk: psk)
            // Nach `pair_ok` schließt der Host die Pairing-Verbindung — aber erst
            // NACH bestätigtem Absenden (closeAfterSend), damit der Client `pair_ok`
            // garantiert erhält und den PSK speichert (sonst hätte der Mac das Gerät
            // gespeichert, der Client aber nicht). Client verbindet für Phase 2 neu.
            send(PairOkMessage(deviceID: deviceID.uuidString, hostName: serviceName), on: ctx.connection, closeAfterSend: true)
            pairingCoordinator.onEvent?(.paired(name: deviceName))

        case .wrongCode(let newOTP):
            // Falscher Code: Client bekommt `bad_otp` (erst-absenden-dann-schließen),
            // das Fenster bleibt offen und zeigt bereits den frisch erzeugten OTP.
            // Der Client baut für den nächsten Versuch eine neue Verbindung auf.
            send(PairErrorMessage(error: ProtocolErrorV2.badOTP.rawValue), on: ctx.connection, closeAfterSend: true)
            pairingCoordinator.onEvent?(.wrongCodeNewIssued(newOTP: newOTP))

        case .pairingClosed:
            send(PairErrorMessage(error: ProtocolErrorV2.pairingClosed.rawValue), on: ctx.connection, closeAfterSend: true)
            pairingCoordinator.onEvent?(.expiredOrClosed)

        case .pairingExpired:
            send(PairErrorMessage(error: ProtocolErrorV2.pairingExpired.rawValue), on: ctx.connection, closeAfterSend: true)
            pairingCoordinator.onEvent?(.expiredOrClosed)
        }
    }

    // MARK: - Phase 2: Sitzung

    private func handleSessionHello(_ data: Data, context ctx: ConnectionContext) {
        guard ctx.phase == .awaitingHello,
              let msg = try? JSONDecoder().decode(SessionHelloMessage.self, from: data),
              msg.type == "session_hello",
              let deviceUUID = UUID(uuidString: msg.deviceID),
              let clientNonce = Data(base64Encoded: msg.nonce) else {
            sendSessionError(.badSession, on: ctx.connection)
            ctx.connection.cancel()
            return
        }

        guard let device = crypto.device(for: deviceUUID) else {
            sendSessionError(.notPaired, on: ctx.connection)
            ctx.connection.cancel()
            return
        }

        var generator = SystemRandomNumberGenerator()
        let hostNonce = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })

        let psk = CryptoManager.symmetricKey(fromDeviceRecord: device.psk)
        let sessionKey = CryptoManager.deriveSessionKey(psk: psk, clientNonce: clientNonce, hostNonce: hostNonce)

        ctx.sessionKey = sessionKey
        ctx.deviceID = deviceUUID
        ctx.deviceName = device.name
        ctx.phase = .sessionActive

        send(SessionReadyMessage(nonce: hostNonce.base64EncodedString()), on: ctx.connection)
        publishState()
    }

    private func handleEncFrame(_ data: Data, context ctx: ConnectionContext) {
        guard ctx.phase == .sessionActive, let sessionKey = ctx.sessionKey else {
            ctx.connection.cancel()
            return
        }
        guard let msg = try? JSONDecoder().decode(EncFrameMessage.self, from: data),
              msg.type == "enc",
              let ct = Data(base64Encoded: msg.ct) else {
            ctx.connection.cancel()
            return
        }
        // Replay-Schutz: seq muss streng monoton steigen.
        if let last = ctx.lastRecvSeq, msg.seq <= last {
            ctx.connection.cancel()
            return
        }
        guard let plaintext = try? SecureFrame.open(
            ct, key: sessionKey, prefix: FrameDirection.clientToHost, seq: msg.seq
        ) else {
            // AEAD-Öffnen-Fehler → Frame verwerfen, Sitzung beenden (Spec).
            ctx.connection.cancel()
            return
        }
        ctx.lastRecvSeq = msg.seq

        guard let scan = try? JSONDecoder().decode(ScanMessage.self, from: plaintext),
              scan.type == "scan" else {
            sendEncrypted(AckMessage(ok: false, error: ProtocolError.invalidMessage.rawValue), context: ctx)
            return
        }

        guard scan.text.utf16.count <= Self.maximumTextLength else {
            sendEncrypted(AckMessage(ok: false, error: ProtocolError.payloadTooLarge.rawValue), context: ctx)
            return
        }

        injector.perform(
            text: scan.text,
            autoTab: scan.autoTab ?? false,
            autoEnter: scan.autoEnter ?? false
        ) { [weak self] ok in
            guard let self else { return }
            let ack = ok
                ? AckMessage(ok: true)
                : AckMessage(ok: false, error: ProtocolError.accessibilityDenied.rawValue)
            self.queue.async {
                self.sendEncrypted(ack, context: ctx)
            }
        }
    }

    // MARK: - Senden

    /// Sendet eine Nachricht. Mit `closeAfterSend: true` wird die Verbindung erst
    /// NACH bestätigtem Absenden geschlossen (im `.contentProcessed`-Completion),
    /// damit das Frame (z. B. `pair_ok`/`pair_error`) nicht durch ein sofortiges
    /// `cancel()` verworfen wird — siehe PROTOCOL-v2.md (Fehlerbehandlung).
    private func send<T: Encodable>(_ message: T, on connection: NWConnection, closeAfterSend: Bool = false) {
        let data = encodeMessage(message)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "msg", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    NSLog("QRKeyboardHost: Sendefehler: %@", String(describing: error))
                }
                if closeAfterSend {
                    connection.cancel()
                }
            }
        )
    }

    private func sendPairError(_ error: ProtocolErrorV2, on connection: NWConnection) {
        sendPairError(rawValue: error.rawValue, on: connection)
    }

    private func sendPairError(rawValue: String, on connection: NWConnection) {
        send(PairErrorMessage(error: rawValue), on: connection)
    }

    private func sendSessionError(_ error: ProtocolErrorV2, on connection: NWConnection) {
        send(SessionErrorMessage(error: error.rawValue), on: connection)
    }

    private func sendEncrypted(_ ack: AckMessage, context ctx: ConnectionContext) {
        guard let sessionKey = ctx.sessionKey else { return }
        let plaintext = ack.jsonData()
        let seq = ctx.sendSeq
        ctx.sendSeq += 1
        guard let ct = try? SecureFrame.seal(
            plaintext, key: sessionKey, prefix: FrameDirection.hostToClient, seq: seq
        ) else { return }
        send(EncFrameMessage(seq: seq, ct: ct.base64EncodedString()), on: ctx.connection)
    }

    // MARK: - UI-Status

    private func publishState() {
        state.activeSessionCount = connections.values.filter {
            $0.phase == .sessionActive && $0.connection.state == .ready
        }.count
        let snapshot = state
        if let onStateChange {
            DispatchQueue.main.async {
                onStateChange(snapshot)
            }
        }
    }
}
