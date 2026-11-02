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
