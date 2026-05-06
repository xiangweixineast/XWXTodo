import SwiftUI

struct NotchView: View {
    let title: String
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: OverlayMetrics.notchMinWidth, maxWidth: OverlayMetrics.notchMaxWidth)
            .frame(height: OverlayMetrics.notchHeight)
            .padding(.horizontal, 22)
            .background(Color.black)
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: 18,
                        bottomTrailing: 18,
                        topTrailing: 0
                    )
                )
            )
            .onHover(perform: onHoverChanged)
    }
}
