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

// MARK: - Paleta

extension Color {
    /// Cor que troca sozinha entre o modo claro e o escuro.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Tema "céu noturno": papel creme no claro, azul-marinho profundo no escuro.
enum Palette {
    static let canvas = Color.adaptive(light: Color(hex: 0xF4F1EA), dark: Color(hex: 0x0A0F1F))
    static let surface = Color.adaptive(light: Color(hex: 0xFFFDF8), dark: Color(hex: 0x131A2E))
    static let raised = Color.adaptive(light: Color(hex: 0xEDE8DD), dark: Color(hex: 0x1B2440))
    static let hairline = Color.adaptive(light: Color(hex: 0xE2DCCF), dark: Color(hex: 0x26304F))
    static let income = Color.adaptive(light: Color(hex: 0x2F8F6B), dark: Color(hex: 0x5CC9A0))
    static let expense = Color.adaptive(light: Color(hex: 0xC2513D), dark: Color(hex: 0xF08A72))
    static let star = Color(hex: 0xE8A93B)
}

/// Cartão do painel: superfície da paleta com contorno fino.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
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
    case amber
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
        case .amber: return Palette.star
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
        case .amber: return "Âmbar"
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

/// Fundo da paleta com os cartões empilhados, usado por todas as abas.
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
        .background(Palette.canvas)
    }
}

/// Indicador em cartão: ícone suave e título na mesma linha, valor em destaque
/// e uma nota opcional embaixo.
struct MetricTile: View {
    let title: String
    let value: Double
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
                isActive ? AnyShapeStyle(TintShapeStyle().opacity(0.15)) : AnyShapeStyle(Palette.raised),
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

/// ‹ mês › com atalho para o mês atual, usado no topo das telas por período.
struct MonthStepper: View {
    @Binding var month: YearMonth

    private var isCurrent: Bool { month == YearMonth(date: Date()) }

    var body: some View {
        HStack(spacing: 6) {
            stepButton("chevron.left", by: -1)
            Text(month.startDate.monthYear)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 130)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.raised, in: Capsule())
            stepButton("chevron.right", by: 1)
            if !isCurrent {
                Button("Hoje") { month = YearMonth(date: Date()) }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
    }

    private func stepButton(_ symbol: String, by offset: Int) -> some View {
        Button {
            month = month.adding(months: offset)
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .frame(width: 30, height: 30)
                .background(Palette.raised, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(offset < 0 ? "Mês anterior" : "Próximo mês")
    }
}
