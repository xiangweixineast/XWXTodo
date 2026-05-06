import SwiftUI

struct ErrorBannerView: View {
    let title: String
    let message: String

    init(title: String = "Error", message: String) {
        self.title = title
        self.message = message
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.red.opacity(0.25), lineWidth: 1)
        }
    }
}

#Preview {
    ErrorBannerView(message: "The database could not be opened.")
        .padding()
        .frame(width: 360)
}
