import SwiftUI
import KausMedia

/// Tela ou cartão sem dados: ícone em órbita com estrelinhas, título,
/// explicação curta e ações opcionais.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    var color: Color = .accentColor
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                Circle()
                    .strokeBorder(color.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .padding(-10)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(color)
                Image(systemName: "sparkle")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.star)
                    .offset(x: 40, y: -30)
                Image(systemName: "sparkle")
                    .font(.system(size: 8))
                    .foregroundStyle(Palette.star.opacity(0.7))
                    .offset(x: -38, y: 28)
            }
            .frame(width: 72, height: 72)
            .padding(.bottom, 6)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)

            HStack(spacing: 10) {
                actions
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

extension EmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String, color: Color = .accentColor) {
        self.init(symbol: symbol, title: title, message: message, color: color) { EmptyView() }
    }
}

/// Versão compacta para dentro de um cartão que já tem título.
struct EmptyNote: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Palette.raised, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
