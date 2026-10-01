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

// MARK: - Aparência

/// Tema escolhido em Ajustes; `system` segue o modo claro/escuro do aparelho.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Cor de destaque escolhida em Ajustes: botões, seleção e o cartão de patrimônio.
enum AppAccent: String, CaseIterable, Identifiable {
    case indigo
    case blue
    case teal
    case green
    case orange
    case red
    case pink
    case purple

    static let storageKey = "accent"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo: return .indigo
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        }
    }

    var title: String {
        switch self {
        case .indigo: return "Índigo"
        case .blue: return "Azul"
        case .teal: return "Turquesa"
        case .green: return "Verde"
        case .orange: return "Laranja"
        case .red: return "Vermelho"
        case .pink: return "Rosa"
        case .purple: return "Roxo"
        }
    }
}

// MARK: - Estrutura das telas

/// Fundo cinza com os cartões empilhados, usado por todas as abas.
struct CardScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary)
    }
}

/// Indicador pequeno em cartão: ícone, título e valor.
struct MetricTile: View {
    let title: String
    let value: Double
    let symbol: String
    let color: Color
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            IconBadge(symbol: symbol, color: color, size: 30)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.brl)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
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

/// Título de seção fora dos cartões.
struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            trailing
        }
        .padding(.top, 4)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Cápsula que abre um menu de filtro; destacada quando o filtro está ativo.
struct FilterChip<Content: View>: View {
    let title: String
    let symbol: String
    var isActive = false
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isActive ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isActive ? AnyShapeStyle(TintShapeStyle().opacity(0.15)) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                in: Capsule()
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// Divisória entre linhas dentro de um cartão, alinhada ao texto e não ao ícone.
struct RowDivider: View {
    var inset: CGFloat = 48

    var body: some View {
        Divider().padding(.leading, inset)
    }
}
