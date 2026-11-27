import SwiftUI

extension View {
    /// Card del pannello in Liquid Glass.
    func glassCard() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
