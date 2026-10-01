import SwiftUI
import KausMedia

/// Ícone e cor de cada categoria. As categorias são livres, então a escolha é
/// feita por palavra-chave no nome; o que não casar recebe uma cor estável
/// derivada do próprio nome.
struct CategoryStyle {
    let symbol: String
    let color: Color

    private static let known: [(keywords: [String], symbol: String, color: Color)] = [
        (["ifood", "aliment", "restaur", "lanche", "comida"], "fork.knife", .orange),
        (["mercado", "supermerc", "feira"], "cart.fill", .green),
        (["transporte", "uber", "combust", "carro", "veiculo"], "car.fill", .blue),
        (["moradia", "aluguel", "condominio", "casa", "energia", "agua"], "house.fill", .brown),
        (["assinatura", "streaming"], "play.rectangle.fill", .purple),
        (["saude", "farmacia", "medic", "pilates", "academia"], "heart.fill", .red),
        (["telefone", "internet", "celular"], "wifi", .cyan),
        (["educa", "curso", "escola", "faculdade"], "book.fill", .indigo),
        (["salario", "receita", "renda", "entrada", "provento", "plr", "ferias", "fgts"], "banknote.fill", .mint),
        (["cartao", "fatura"], "creditcard.fill", .gray),
        (["caixinha", "poupanca", "investimento", "tesouro", "reserva", "cofrinho"], "lock.shield.fill", .teal),
        (["lazer", "viagem", "passeio", "cinema"], "airplane", .pink),
        (["movel", "moveis", "decor"], "sofa.fill", .brown),
        (["roupa", "vestu", "compras", "shopping", "shopee"], "bag.fill", .pink),
        (["pet", "veterin"], "pawprint.fill", .orange),
        (["imposto", "taxa", "tarifa", "iof"], "building.columns.fill", .gray),
        (["pix", "transfer", "ted"], "arrow.left.arrow.right", .gray)
    ]

    private static let palette: [Color] = [.orange, .green, .blue, .purple, .pink, .teal, .indigo, .mint, .cyan, .red]

    static func of(_ category: String?) -> CategoryStyle {
        let name = TextNormalizer.normalize(category ?? CategoryRule.uncategorizedDebit)
        if let match = known.first(where: { entry in entry.keywords.contains { name.contains($0) } }) {
            return CategoryStyle(symbol: match.symbol, color: match.color)
        }
        // Soma dos escalares em vez de `hashValue`, que muda a cada execução.
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return CategoryStyle(symbol: "tag.fill", color: palette[seed % palette.count])
    }
}

extension AccountKind {
    var symbol: String {
        switch self {
        case .checking: return "building.columns.fill"
        case .savings: return "lock.shield.fill"
        case .creditCard: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }

    var tint: Color {
        switch self {
        case .checking: return .blue
        case .savings: return .teal
        case .creditCard: return .purple
        case .cash: return .green
        case .investment: return .indigo
        }
    }
}

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

/// Fundo branco arredondado dos cartões do painel.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

/// Título padrão dos cartões, com ação opcional à direita.
struct CardHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

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

extension Double {
    /// Valor com sinal explícito, para variações.
    var signedBRL: String { self > 0 ? "+\(brl)" : brl }
}
