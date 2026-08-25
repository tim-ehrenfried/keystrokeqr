import Foundation
import Network
import Combine

/// Client → Host: gescannter Code (siehe docs/PROTOCOL.md).
struct ScanMessage: Encodable {
    let type = "scan"
    let text: String
    let autoEnter: Bool
    let autoTab: Bool
}

/// Host → Client: Acknowledgement (siehe docs/PROTOCOL.md).
struct AckMessage: Decodable {
    let type: String
    let ok: Bool
    let error: String?
}

/// Verwaltet Bonjour-Discovery (`_qr-keyboard._tcp`) und die WebSocket-Verbindung
/// zum Mac-Host via Network.framework. Der Port kommt IMMER aus der
/// Bonjour-Auflösung (NWEndpoint.service), niemals hartkodiert.
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
        var id: String { name }
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var services: [DiscoveredService] = []
    @Published var showServicePicker = false
    /// Host hat gemeldet, dass die Bedienungshilfen-Berechtigung auf dem Mac fehlt.
    @Published var hostAccessibilityDenied = false

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var isActive = false
    private var reconnectAttempts = 0
    private let queue = DispatchQueue(label: "de.timehrenfried.qr-keyboard-scanner.network")

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

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        guard isActive else { return }
        services = results
            .compactMap { result -> DiscoveredService? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredService(name: name, endpoint: result.endpoint)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard connection == nil else { return }
        if services.count == 1 {
            connect(to: services[0])
        } else if services.count > 1 {
            showServicePicker = true
        }
    }

    // MARK: - Verbindung

    /// Verbindet zum gewählten Bonjour-Service. Der WebSocket läuft direkt auf
    /// dem Service-Endpoint — Auflösung von Host & Port übernimmt das System.
    func connect(to service: DiscoveredService) {
        guard isActive else { return }
        showServicePicker = false
        connection?.cancel()

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        parameters.includePeerToPeer = true

        let newConnection = NWConnection(to: service.endpoint, using: parameters)
        connection = newConnection
        state = .connecting(service.name)

        newConnection.stateUpdateHandler = { [weak self] connectionState in
            Task { @MainActor [weak self] in
                self?.handleConnectionState(connectionState, serviceName: service.name, connection: newConnection)
            }
        }
        receiveLoop(on: newConnection)
        newConnection.start(queue: queue)
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
            state = .connected(serviceName)
        case .failed, .cancelled:
            connectionLost(connection)
        case .waiting:
            // Network.framework versucht es selbst erneut; wir brechen nach
            // kurzer Zeit ab und starten den Browse-Vorgang neu.
            state = .connecting(serviceName)
        default:
            break
        }
    }

    private func connectionLost(_ lost: NWConnection) {
        guard connection === lost else { return }
        connection?.cancel()
        connection = nil
        guard isActive else { return }
        state = .disconnected
        scheduleRetry()
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

    // MARK: - Senden / Empfangen

    /// Sendet einen gescannten Code als WebSocket-Text-Frame (JSON, UTF-8).
    func send(text: String, autoEnter: Bool, autoTab: Bool) {
        guard let connection, case .connected = state else { return }
        let message = ScanMessage(text: text, autoEnter: autoEnter, autoTab: autoTab)
        guard let data = try? JSONEncoder().encode(message) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "scan", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    nonisolated private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                Task { @MainActor [weak self] in
                    self?.handleIncoming(data)
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

    private func handleIncoming(_ data: Data) {
        guard let ack = try? JSONDecoder().decode(AckMessage.self, from: data),
              ack.type == "ack" else { return }
        if ack.ok {
            hostAccessibilityDenied = false
        } else if ack.error == "accessibility_denied" {
            hostAccessibilityDenied = true
        }
    }
}
