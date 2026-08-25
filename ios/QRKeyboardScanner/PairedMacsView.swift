import SwiftUI

/// „Gekoppelte Macs verwalten“ — Liste mit Entkoppeln-Aktion
/// (docs/PROTOCOL-v2.md, „Geräteverwaltung“). Erreichbar aus der Hilfe.
struct PairedMacsView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @Environment(\.dismiss) private var dismiss

    @State private var macs: [CryptoManager.PairedMac] = []

    var body: some View {
        NavigationStack {
            List {
                if macs.isEmpty {
                    Text("Noch kein Mac gekoppelt. Öffne auf dem Mac das Menü „Gerät koppeln…“.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(macs) { mac in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mac.hostName)
                                    .font(.headline)
                                Text("Gekoppelt: \(mac.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: delete)
                    } footer: {
                        Text("Entkoppeln löscht den gemeinsamen Schlüssel auf diesem iPhone; eine laufende Verbindung zu diesem Mac wird sofort getrennt. Um wieder zu verbinden, ist erneutes Pairing am Mac nötig.")
                    }
                }
            }
            .navigationTitle("Gekoppelte Macs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
                if !macs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .task { reload() }
        }
    }

    private func reload() {
        macs = connectionManager.pairedMacs()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            connectionManager.unpair(serviceName: macs[index].serviceName)
        }
        reload()
    }
}
