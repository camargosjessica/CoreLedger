import Foundation

/// Regra de categorização. É **dado**, não código: o cliente pode criar, editar,
/// reordenar e remover regras sem que seja necessário recompilar nada.
public struct CategoryRule: Codable, Sendable, Hashable, Identifiable {
    /// Como o termo é comparado com a descrição do lançamento.
    public enum MatchKind: String, Codable, Sendable, CaseIterable {
        /// O termo precisa aparecer delimitado por fronteiras de palavra.
        /// `"net"` casa com `"NET SERVICOS"` mas não com `"INTERNET"`.
        case word
        /// O termo pode aparecer em qualquer posição, inclusive no meio de outra palavra.
        /// Útil para prefixos truncados pelo banco, como `"supermerc"`.
        case contains
        /// O termo é uma expressão regular (sintaxe ICU), aplicada sobre a
        /// descrição já normalizada (minúscula e sem acentos).
        case regex
    }

    /// Sinal do lançamento ao qual a regra se aplica.
    public enum AmountScope: String, Codable, Sendable, CaseIterable {
        case any
        case credit
        case debit

        public func matches(_ amount: Double) -> Bool {
            switch self {
            case .any: return true
            case .credit: return amount >= 0
            case .debit: return amount < 0
            }
        }
    }

    public var id: UUID?
    /// Termo procurado na descrição. Comparado sem acentos e sem diferenciar maiúsculas.
    public var term: String
    public var category: String
    public var matchKind: MatchKind
    public var amountScope: AmountScope
    /// Menor valor é avaliado primeiro. Empates são desempatados pelo termo mais longo,
    /// de modo que a ordenação é determinística entre servidor e cliente.
    public var priority: Int
    public var isEnabled: Bool
    /// Marca categorias que apenas movem dinheiro entre contas (PIX, TED, pagamento de fatura).
    /// Lançamentos assim são ignorados na projeção, porque inflariam entradas e saídas ao mesmo tempo.
    public var isTransfer: Bool

    public init(
        id: UUID? = nil,
        term: String,
        category: String,
        matchKind: MatchKind = .word,
        amountScope: AmountScope = .any,
        priority: Int = 100,
        isEnabled: Bool = true,
        isTransfer: Bool = false
    ) {
        self.id = id
        self.term = term
        self.category = category
        self.matchKind = matchKind
        self.amountScope = amountScope
        self.priority = priority
        self.isEnabled = isEnabled
        self.isTransfer = isTransfer
    }
}

extension CategoryRule {
    /// Categoria atribuída quando nenhuma regra casa.
    public static let uncategorizedCredit = "Outras entradas"
    public static let uncategorizedDebit = "Outros"

    /// Conjunto inicial de regras, usado apenas como seed do banco na primeira migração.
    /// A partir daí a fonte da verdade é a tabela `category_rules`.
    public static let seed: [CategoryRule] = {
        let groups: [(category: String, priority: Int, isTransfer: Bool, terms: [(String, MatchKind)])] = [
            ("Alimentação", 10, false, [
                ("ifood", .contains), ("rappi", .contains), ("restaurante", .contains),
                ("padaria", .contains), ("lanchonete", .contains), ("burger", .contains),
                ("pizzaria", .contains), ("cafeteria", .contains)
            ]),
            ("Mercado", 10, false, [
                ("mercado", .contains), ("supermerc", .contains), ("atacad", .contains),
                ("carrefour", .contains), ("assai", .contains), ("pao de acucar", .contains),
                ("hortifruti", .contains)
            ]),
            ("Transporte", 20, false, [
                ("uber", .word), ("99app", .contains), ("99 pop", .contains), ("cabify", .word),
                ("posto", .word), ("combust", .contains), ("shell", .word), ("ipiranga", .word),
                ("estacion", .contains), ("pedagio", .contains)
            ]),
            ("Moradia", 20, false, [
                ("aluguel", .contains), ("condominio", .contains), ("energia", .contains),
                ("enel", .word), ("cemig", .word), ("sabesp", .word), ("copasa", .word),
                ("iptu", .word)
            ]),
            ("Assinaturas", 15, false, [
                ("netflix", .contains), ("spotify", .contains), ("amazon prime", .contains),
                ("disney", .contains), ("hbo", .word), ("youtube", .contains),
                ("apple.com", .contains), ("icloud", .contains)
            ]),
            ("Saúde", 20, false, [
                ("farmacia", .contains), ("drogaria", .contains), ("hospital", .contains),
                ("clinica", .contains), ("unimed", .contains), ("laborat", .contains),
                ("odonto", .contains)
            ]),
            ("Telefone/Internet", 30, false, [
                ("vivo", .word), ("claro", .word), ("tim", .word), ("oi fibra", .contains),
                ("internet", .word), ("net servicos", .contains), ("telefon", .contains)
            ]),
            ("Educação", 25, false, [
                ("escola", .word), ("faculdade", .word), ("universidade", .word),
                ("curso", .word), ("mensalidade", .contains)
            ]),
            ("Salário", 5, false, [
                ("salario", .contains), ("pagamento folha", .contains), ("provento", .contains),
                ("adiantamento salarial", .contains)
            ]),
            ("Cartão de crédito", 5, true, [
                ("pagamento de fatura", .contains), ("pgto fatura", .contains),
                ("pagto cartao", .contains)
            ]),
            ("Transferências", 90, true, [
                ("pix", .word), ("ted", .word), ("doc", .word), ("transf", .contains)
            ])
        ]

        return groups.flatMap { group in
            group.terms.map { term, kind in
                CategoryRule(
                    term: term,
                    category: group.category,
                    matchKind: kind,
                    priority: group.priority,
                    isTransfer: group.isTransfer
                )
            }
        }
    }()
}
