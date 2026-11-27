import SwiftUI

/// Marchio stilizzato di OpenCode, come nella barra: stessa geometria di MenuBarIcon.drawMark
/// (AppKit, per l'NSImage dell'etichetta), in settimi del lato. Un ritocco va fatto in entrambi.
struct OpenCodeMark: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack(alignment: .bottom) {
                Rectangle().strokeBorder(lineWidth: side / 7)
                Rectangle()
                    .frame(width: side - side * 4 / 7, height: side / 2 - side * 2 / 7)
                    .padding(.bottom, side * 2 / 7)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
