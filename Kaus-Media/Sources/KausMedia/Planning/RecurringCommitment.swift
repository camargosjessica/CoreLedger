import Foundation

/// Compromisso que se repete todo mês: condomínio, luz, mensalidade, salário,
/// aporte na caixinha. É o que a planilha guardava como uma linha por ano.
public struct RecurringCommitment: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Sai do bolso e empobrece o mês.
        case expense
        /// Entra no bolso.
        case income
        /// Sai da conta mas continua sendo seu: aporte em caixinha, tesouro direto.
        case saving

        public var displayName: String {
            switch self {
            case .expense: return "Despesa"
            case .income: return "Receita"
            case .saving: return "Guardar"
            }
        }
    }

    public var id: UUID?
    public var name: String
    public var category: String
    public var kind: Kind
    /// Valor mensal padrão, sempre positivo — o sinal vem de `kind`.
    public var amount: Double
    public var dayOfMonth: Int
    public var start: YearMonth
    /// `nil` significa recorrência sem fim previsto.
    public var end: YearMonth?
    public var tags: [String]
    public var isEnabled: Bool
    /// Valor combinado para um mês específico, sobrepondo `amount`. É o reajuste
    /// da planilha ("a partir de julho a Copel vai para 350"); `0` zera o mês.
    public var overrides: [String: Double]
    public var accountID: UUID?
    public var notes: String?

    public init(
        id: UUID? = nil,
        name: String,
        category: String,
        kind: Kind = .expense,
        amount: Double,
        dayOfMonth: Int = 1,
        start: YearMonth,
        end: YearMonth? = nil,
        tags: [String] = [],
        isEnabled: Bool = true,
        overrides: [String: Double] = [:],
        accountID: UUID? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.kind = kind
        self.amount = amount
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        self.start = start
        self.end = end
        self.tags = TagSet.normalize(tags)
        self.isEnabled = isEnabled
        self.overrides = overrides
        self.accountID = accountID
        self.notes = notes
    }

    public var isEssential: Bool { tags.contains(TagSet.essential) }

    public func isActive(in month: YearMonth) -> Bool {
        guard isEnabled, month >= start else { return false }
        if let end { return month <= end }
        return true
    }

    /// Valor planejado para o mês, já com sinal: despesa e aporte negativos,
    /// receita positiva. `0` quando o compromisso não vale para aquele mês.
    public func plannedAmount(in month: YearMonth) -> Double {
        guard isActive(in: month) else { return 0 }
        let value = overrides[month.description] ?? amount
        return kind == .income ? abs(value) : -abs(value)
    }

    public func date(in month: YearMonth) -> Date { month.date(day: dayOfMonth) }
}

/// Tags de lançamentos e compromissos. São texto livre: o app sugere, o usuário
/// cria as suas. A única com significado para o cálculo é `essencial`.
public enum TagSet {
    /// Marca o que é preciso pagar para sobreviver ao mês.
    public static let essential = "essencial"

    /// Tags sugeridas por categoria quando o lançamento é criado ou importado.
    /// Servem de ponto de partida — o usuário edita depois.
    public static let defaultsByCategory: [String: [String]] = [
        "Moradia": [essential],
        "Mercado": [essential],
        "Saúde": [essential],
        "Telefone/Internet": [essential],
        "Transporte": [essential],
        "Educação": [essential],
        "Alimentação": ["variável"],
        "Assinaturas": ["variável"],
        "Guardado": ["reserva"]
    ]

    public static func suggested(for category: String?) -> [String] {
        guard let category else { return [] }
        return defaultsByCategory[category] ?? []
    }

    /// Minúsculas, sem espaços nas pontas, sem repetição e em ordem estável —
    /// para que "Essencial" e "essencial " não virem duas tags diferentes.
    public static func normalize(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
