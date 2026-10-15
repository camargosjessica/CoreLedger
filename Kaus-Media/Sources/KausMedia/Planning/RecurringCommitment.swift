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
    /// Reajustes permanentes (`YYYY-MM` -> valor): o valor novo vale daquele
    /// mês em diante, e os meses anteriores continuam com o valor de antes.
    public var priceChanges: [String: Double]
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
        priceChanges: [String: Double] = [:],
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
        self.priceChanges = priceChanges
        self.accountID = accountID
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            category: try container.decode(String.self, forKey: .category),
            kind: try container.decode(Kind.self, forKey: .kind),
            amount: try container.decode(Double.self, forKey: .amount),
            dayOfMonth: try container.decode(Int.self, forKey: .dayOfMonth),
            start: try container.decode(YearMonth.self, forKey: .start),
            end: try container.decodeIfPresent(YearMonth.self, forKey: .end),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            overrides: try container.decodeIfPresent([String: Double].self, forKey: .overrides) ?? [:],
            priceChanges: try container.decodeIfPresent([String: Double].self, forKey: .priceChanges) ?? [:],
            accountID: try container.decodeIfPresent(UUID.self, forKey: .accountID),
            notes: try container.decodeIfPresent(String.self, forKey: .notes)
        )
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
        let value = overrides[month.description] ?? baseAmount(in: month)
        return kind == .income ? abs(value) : -abs(value)
    }

    /// Valor padrão em vigor no mês, sem sinal: o último reajuste até aquele
    /// mês ou, sem reajuste, `amount`.
    public func baseAmount(in month: YearMonth) -> Double {
        priceChanges
            .compactMap { key, value in YearMonth(key).map { (month: $0, value: value) } }
            .filter { $0.month <= month }
            .max { $0.month < $1.month }?
            .value ?? amount
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
