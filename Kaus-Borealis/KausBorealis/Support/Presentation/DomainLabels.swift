import Foundation
import KausMedia

// Nomes que a interface mostra para os tipos do domínio. Moram no app, e não
// no Kaus-Media, porque texto de tela é apresentação: o servidor não precisa
// deles e eles passam pelo String Catalog (Localizable.xcstrings).

extension AccountKind {
    var displayName: String {
        switch self {
        case .checking: return String(localized: "Conta corrente")
        case .savings: return String(localized: "Caixinha ou poupança")
        case .creditCard: return String(localized: "Cartão de crédito")
        case .cash: return String(localized: "Dinheiro")
        case .investment: return String(localized: "Investimento")
        }
    }
}

extension RecurringCommitment.Kind {
    var displayName: String {
        switch self {
        case .expense: return String(localized: "Despesa")
        case .income: return String(localized: "Receita")
        case .saving: return String(localized: "Guardar")
        }
    }
}

extension ResetScope {
    var title: String {
        switch self {
        case .transactions: return String(localized: "Lançamentos e importações")
        case .accounts: return String(localized: "Lançamentos e contas")
        case .everything: return String(localized: "Tudo, inclusive regras")
        }
    }
}

extension SpendingGrouping {
    var title: String {
        switch self {
        case .category: return String(localized: "Categoria")
        case .subcategory: return String(localized: "Subcategoria")
        case .tag: return String(localized: "Tag")
        }
    }
}

extension PositionStatus {
    var title: String {
        switch self {
        case .positive: return String(localized: "Positiva")
        case .even: return String(localized: "Empatada")
        case .negative: return String(localized: "Negativa")
        }
    }
}
