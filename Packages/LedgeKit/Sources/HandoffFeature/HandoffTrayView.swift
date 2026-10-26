import SwiftUI

public struct HandoffTrayView: View {
    @Bindable private var store: HandoffStore
    private let shareAction: ((ShareMode) -> Void)?
    private let qrAction: (() -> Void)?
    public init(store: HandoffStore, shareAction: ((ShareMode) -> Void)? = nil, qrAction: (() -> Void)? = nil) { self.store = store; self.shareAction = shareAction; self.qrAction = qrAction }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Handoff").font(.headline)
            if store.items.isEmpty { Text("Drop text, links, or files here") }
            HStack {
                Button("Share") { shareAction?(.general) }.accessibilityIdentifier("handoff.share").disabled(store.items.isEmpty || shareAction == nil)
                Button("AirDrop") { shareAction?(.airDrop) }.accessibilityIdentifier("handoff.airdrop").disabled(store.items.isEmpty || shareAction == nil)
                Button("Show QR") { qrAction?() }.accessibilityIdentifier("handoff.qr").disabled(store.items.isEmpty || qrAction == nil)
            }
            Text("QR codes reveal the exact text or link to anyone who can see or scan them. Confirmation is required and the preview closes after 60 seconds.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear Expired") { Task { await store.clearExpired() } }.accessibilityIdentifier("handoff.clear-expired")
            if let message = store.errorMessage { Text(message).foregroundStyle(.red) }
        }.padding().onAppear { Task { await store.refresh() } }
    }
}
