import SwiftUI
import KausMedia

/// Quadrado arredondado colorido com o ícone, como nos apps de banco.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct CategoryIcon: View {
    let category: String?
    var size: CGFloat = 36

    var body: some View {
        let style = CategoryStyle.of(category)
        IconBadge(symbol: style.symbol, color: style.color, size: size)
    }
}

// MARK: - Paleta
