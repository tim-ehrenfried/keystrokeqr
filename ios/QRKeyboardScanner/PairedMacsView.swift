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
                    Text("No Mac paired yet. On the Mac, open the “Pair Device…” menu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(macs) { mac in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mac.hostName)
                                    .font(.headline)
                                Text("Paired: \(mac.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete(perform: delete)
                    } footer: {
                        Text("Unpairing deletes the shared key on this iPhone; any active connection to this Mac is disconnected immediately. To connect again, pair once more on the Mac.")
                    }
                }
            }
            .navigationTitle("Paired Macs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
