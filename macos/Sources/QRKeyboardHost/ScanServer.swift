import Foundation
import Network

/// WebSocket-Server gemäß docs/PROTOCOL.md (v1):
/// - NWListener (TCP + NWProtocolWebSocket, autoReplyPing)
/// - Fester Port 8080, Fallback auf beliebigen freien Port
/// - Bonjour-Advertising als `_qr-keyboard._tcp` mit TXT `v=1`
/// - Mehrere gleichzeitige Clients; Scans werden sequenziell getippt.
final class ScanServer: @unchecked Sendable {

    static let serviceType = "_qr-keyboard._tcp"
    static let preferredPort: UInt16 = 8080

    /// DoS-Schutz: maximale Größe eines WebSocket-Frames in Bytes.
    /// Größere Frames verwirft Network.framework, bevor sie die App erreichen.
    static let maximumMessageSize = 65_536
    /// DoS-Schutz: maximale Länge von `text` in UTF-16-Einheiten. Deckt jede
    /// reale QR-/Barcode-Kapazität ab (QR max. ~7089 Zeichen numerisch);
    /// verhindert, dass ein bösartiger Client den Mac minutenlang „volltippt".
    static let maximumTextLength = 8_192

    /// Zustand für die UI. Wird immer auf dem Main Thread gemeldet.
    struct State: Sendable {
        var connectionCount: Int = 0
        var port: UInt16? = nil
        var serviceName: String = ""
    }

    /// UI-Callback; wird auf DispatchQueue.main aufgerufen.
    var onStateChange: (@Sendable (State) -> Void)?

    private let queue = DispatchQueue(label: "de.timehrenfried.qr-keyboard-host.server")
    private let injector: KeyInjector
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var state = State()
    private let serviceName: String

    init(injector: KeyInjector) {
        self.injector = injector
        self.serviceName = Host.current().localizedName ?? "QR Keyboard Host"
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
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
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

        // Bonjour-Advertising: Service-Name = Hostname des Macs, TXT v=1.
        // TXT-Record im Standardformat: Längenbyte + "v=1".
        var txtData = Data()
        let entry = Data("v=1".utf8)
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
        connections[id] = connection

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

    // MARK: - Nachrichten

    private func handleMessage(_ data: Data, on connection: NWConnection) {
        guard let scan = try? JSONDecoder().decode(ScanMessage.self, from: data),
              scan.type == "scan" else {
            send(AckMessage(ok: false, error: ProtocolError.invalidMessage.rawValue),
                 on: connection)
            return
        }

        // Längenlimit (DoS-Schutz): übergroße Payloads werden abgelehnt,
        // statt den Mac minutenlang mit Keystrokes zu fluten.
        guard scan.text.utf16.count <= Self.maximumTextLength else {
            send(AckMessage(ok: false, error: ProtocolError.payloadTooLarge.rawValue),
                 on: connection)
            return
        }

        // Scans werden vom KeyInjector strikt sequenziell abgearbeitet
        // (serielle Queue); das Ack folgt nach Abschluss des Tippens.
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
                self.send(ack, on: connection)
            }
        }
    }

    private func send(_ ack: AckMessage, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ack", metadata: [metadata])
        connection.send(
            content: ack.jsonData(),
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    NSLog("QRKeyboardHost: Ack-Sendefehler: %@", String(describing: error))
                }
            }
        )
    }

    // MARK: - UI-Status

    private func publishState() {
        state.connectionCount = connections.values.filter { $0.state == .ready }.count
        let snapshot = state
        if let onStateChange {
            DispatchQueue.main.async {
                onStateChange(snapshot)
            }
        }
    }
}
