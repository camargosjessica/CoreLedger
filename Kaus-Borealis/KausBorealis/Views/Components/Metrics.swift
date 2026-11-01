import SwiftUI
import KausMedia

/// Selo arredondado de variação ("+R$ 173,00").
struct DeltaPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

extension Money {
    /// Valor com sinal explícito, para variações.
    var signedBRL: String { self > 0 ? "+\(brl)" : brl }
}

// MARK: - Aparência

/// Indicador em cartão: ícone suave e título na mesma linha, valor em destaque
/// e uma nota opcional embaixo.
struct MetricTile: View {
    let title: String
    let value: Money
    let symbol: String
    let color: Color
    var valueColor: Color = .primary
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.16), in: Circle())
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value.brl)
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .card()
    }
}

/// Grade de `MetricTile` que vira coluna única em telas estreitas.
struct MetricGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            content
        }
    }
}
